# Weapon Tweaker Changelog

## 0.12.284-beta (2026-07-19) - #664 dead parity tick + #374/#388 EnergyData seeding [untested]

- #664 root cause: `weapon_tweaker_backend.lua`'s `M.install` (run at the
  bottom of `weapon_tweaker.lua`) assigned `mod.update` with a naked
  overwrite AFTER `_wt431_damage_profile_parity.lua` had wrapped it with the
  peer-parity beacon tick. The stomp killed the tick, froze the beacon's
  applied state at fail-safe "disabled", and held every parity-gated damage
  profile toggle (Executioner light headshot #664, 1H Axe cleave issue 621,
  brace/priest/brett issue 431 set) at parity=false forever - even solo
  (54/54 logs: `[wt:664] ... enabled=false parity=false`). The backend
  assignment now preserves the previously-installed update
  (`prev_update` chain), so solo settles to parity=true on the first beacon
  poll and the toggle engages when enabled.
- #374: seeded `EnergyData[career]` (recharge_rate 1.5, recharge_delay 0.2,
  max_value 25, depletion_cooldown 5 - the exact vanilla Kerillian row,
  `energy_data.lua:4-27`) for every career the final `can_wield` state grants
  an energy weapon (`bow_energy`/`aim_energy` actions), before energy
  extensions initialize. All four spawn paths read the row locally
  (owner `bulldozer_player.lua:207`, bot `player_bot.lua:140`, husk
  `game_object_initializers_extractors.lua:2128/2296`), so owner, husk, and
  bot units all recharge natively; covers wt- and CWV-granted careers alike.
  New engine-free policy module `_wt_energy_seed.lua`; rows are private
  per-career clones, marker-tagged, added-only (native rows never touched),
  reverted exactly in `on_disabled`. The issue 584 owner-side workaround
  self-gates on a non-zero native rate, so no double regen.
- #388 (partial): with real recharge/delay values the `is_drainable`
  transitions resume, so the `on_energy_drainable` / `on_energy_not_drainable`
  equipment flow events (FX/sounds/HUD presentation) fire on non-native
  careers. The hardcoded `energy_bar_ui` color override remains open.

**Solo verify:** load a keep session and check the log shows
`[wt:664] applied: ... parity=true` shortly after
`[wt:431] peer-parity beacon installed`; enable the Executioner toggle and
confirm `enabled=true parity=true` plus the +30% light headshot in-mission.
For #374, grant Moonfire to a non-elf career, fire until drained, and confirm
the bar refills at the native rate with draw/charge FX and sounds (#388).
## 0.12.283-beta (2026-07-19) - #181 Skullsplitter right-hand presentation [verify-fix]

- Relinked the illusion-correct third-person Skullsplitter hammer to Kruber's
  native right-hand attachment while keeping the tome hidden.
- Corrected the separately owned inventory-preview entry without changing the
  first-person presentation or Warrior Priest behavior.

## 0.12.282-beta (2026-07-19) - #748 complete 3P animation vocabulary [verify-fix; coop-required]

- Extended the existing declarative animation-remap owner with the missing
  CWV animation vocabulary used by Outrider and cross-character weapon states.
- Kept one wield hook and fail-closed donor fallback; added regression evidence
  for recognized events and bounded unknown-event diagnostics.

## 0.12.281-beta (2026-07-19) - #735 shield-only rotation routing [verify-fix; coop-required]

- Added an explicit hand discriminator to baked transform descriptors so the
  Saltzpyre shield seating rotation targets only the left-hand shield and never
  the paired sword.
- Unified scale, offset, and rotation receiver/hand policy across owner, bot,
  remote husk, and paired inventory preview paths.
- Added bounded retained-quaternion evidence and regression coverage for exact
  hand composition without changing first-person behavior.

## 0.12.280-beta (2026-07-19) - #835 callable Vector3 constructor [verify-fix]

- Synchronized the shared appearance primitive's protected callable constructor
  boundary so retail callable-table engine namespaces are accepted without
  weakening malformed-constructor failure handling.

## 0.12.279-beta (2026-07-18) - #661 effective runtime career actions [verify-fix]

- Expanded the initial Saltzpyre catalog fix to every effective runtime
  template. Old Musket now reconciles both rifle and bayonet stance templates;
  Outrider follows the same family contract.
- Career actions now follow the item's live `can_wield` set rather than a stale
  catalog declaration. The existing sole local wield hook performs one
  idempotent last-mile check against `BackendUtils.get_item_template`, covering
  late availability and stance changes without per-frame work or new RPCs.
- Claims are tracked by template identity and released provider-safely. WT no
  longer clobbers foreign non-canonical action rows.

**Solo verify:** Confirm `[wt] v0.12.279-beta loaded`, enable both CWV ranged
ports for Bounty Hunter, and fire Locked and Loaded with Outrider and Old Musket
in both stances. Repeat after slot swaps and a mission transition. The log must
show bounded `[wt:661] effective-action ... result=ok` entries and no incomplete
career-action error.

## 0.12.278-beta (2026-07-18) - #661 Saltzpyre CWV ranged career actions [verify-fix]

- Fixed WT-owned Saltzpyre access to CWV's Empire Old Musket and Outrider
  Grenade Launcher so standard Witch Hunter careers receive their native
  weapon-bound career action rows when those items are enabled through WT.
- Kept Kruber as the default authored owner for both weapons. Saltzpyre access
  remains optional WT-controlled availability, not a CWV default grant and not
  a Warrior Priest grant.
- Added regression coverage proving Bounty Hunter is present in the effective
  conditional career set for both weapons while remaining out of the default
  crafted/owned career list.

**Solo verify:** Confirm `[wt] v0.12.278-beta loaded`. With CWV active, enable
Old Musket and Outrider Grenade Launcher for Bounty Hunter through WT, equip
each weapon, and fire Locked and Loaded. Repeat after swapping away/back and
after loading into a mission. The career skill must trigger normally and the log
must not contain `[wt:career-actions] incomplete` for either item.

## 0.12.277-beta (2026-07-18) - #701 Kruber Crossbow left-hand grip [verify-fix; coop-required]

- Added the user-tuned additive third-person grip correction for Kruber using
  Saltzpyre's regular Crossbow: `+0.100` Y and `+0.025` Z on its left-hand unit.
- Kept the transform receiver-scoped and renderer-local across owner, bot,
  remote husk, and inventory-preview creation paths. Native Saltzpyre, first
  person, Volley Crossbow, shared attachment tables, and network payloads are
  unchanged.
- Added one bounded post-write engine-position readback per tracked Crossbow,
  focused offline/runtime coverage, and a structural appearance contract.

**Co-op verify:** Confirm `[wt:LOAD] v0.12.277-beta` on both peers. On Kruber,
equip Saltzpyre's regular Crossbow and check owner third person plus inventory
preview while the observer checks the remote husk. Fire/reload, swap away and
back, transition into a mission, and hot-join once. The Crossbow must retain
the corrected grip everywhere, `[wt:701] retained` must show retained and
target positions, and `/wt_regression_test` must pass
`issue701_kruber_crossbow_left_grip_offset`.

## 0.12.276-beta (2026-07-18) - #732 CWV Infantry spear Saltzpyre crash guard [verify-fix]

- CWV's Infantry Combat Style reports its deep-cloned effective template as
  `cwv_infantry_spear_template`, while WT's receiver-safe Saltzpyre 3P remap
  and wield contracts were keyed only by the elf-spear donor template. The
  first light therefore reached Saltzpyre's animation graph as
  `attack_swing_down_left_axe` and faulted in `Unit.animation_event`.
- The effective clone now shares the donor's remap and wield tables by identity,
  preserving all three standard Saltzpyre billhook-vocabulary routes and the
  native Kerillian no-remap branch without duplicating data.
- Offline and `/wt_regression_test` coverage lock table identity, the first-light
  target `attack_swing_stab`, and WHC/Bounty Hunter/Zealot wield routing.

**Solo verify:** Confirm `[wt:LOAD] v0.12.276-beta`. On Witch Hunter Captain,
Bounty Hunter, or Zealot, equip Tuskgor Spear, select Infantry Combat Style,
then perform the first light and the complete light/heavy/block/push chains.
The game must not crash and `/wt_regression_test` must pass
`issue732_cwv_infantry_spear_saltzpyre_remap`. One player is sufficient for
the reported owner-side crash.

## 0.12.275-beta (2026-07-18) - #724 release/source reconciliation [tooling]

- Rebuilt the public beta from the current merged source so its tracked bundle,
  Workshop artifact, and GitHub release manifest all carry the #660 appearance
  census added after `0.12.274-beta` was published.
- The census is bounded, observation-only tooling. This entry makes no new
  player-facing behavior claim and does not change #660's verification state.

## 0.12.274-beta (2026-07-17) - #661 reconciliation build: both parallel fixes [verify-fix]

- Reconciliation reship: two different builds were briefly uploaded as `0.12.273-beta` by parallel sessions. This unambiguous version carries BOTH #661 changes: the shared library's private-clone action ownership (below) AND the inject-site clone-identity restore - `_inject_career_actions` restores canonical `ActionTemplates` identity on any mismatched career-action row before installing (CWV deep-clones donor templates; vanilla installs career rows by identity, `weapons.lua:263`; no repo mod authors custom `action_career_*` rows). Residual conflicts now report `conflict:<action>@<template>`.

**Solo verify:** confirm `[wt:LOAD] v0.12.274-beta`, enter the keep with CWV enabled, open loadouts and swap weapons several times: zero `[wt:career-actions]` lines; career abilities still fire on CWV variants (Dawi maces, Bret Longsword styles).

## 0.12.273-beta (2026-07-17) - #661 private-clone action ownership [verify-fix]

- Updated the bundled provider-neutral career-action library so private weapon
  producers can discard deep-cloned donor claims and restore only
  source-proven canonical action rows before WT shares ownership.
- WT's existing apply/release behavior is unchanged. Foreign replacements
  still fail closed and one provider cannot remove another provider's row.
- Shared offline coverage now includes cloned claim contamination, repeated
  reconciliation, late provider registration, and replacement preservation.

**Solo verify:** With CWV enabled, wield a CWV weapon on Bardin and Kruber and
use each career ability before and after swapping weapons. `/wt_regression_test`
must pass without `conflict:action_career_dr_3` or
`conflict:action_career_es_4`.

## 0.12.272-beta (2026-07-17) - #661 career-action reconciliation [verify-fix]

- Reconciled career actions after the deferred post-CWV availability pass, including alternate ability rows.
- Added identity-safe provider claims so WT cleanup cannot delete native, replaced, or still-required CWV/WOC action rows.
- Expanded engine-free coverage for late registration, repeated reconciliation, release order, replacement, and conflicts.

**Solo verify:** equip cross-character weapons on at least two careers, use every career ability before and after a weapon swap, and run `/wt_regression_test`. Abilities must remain usable and career-action checks must pass.

## 0.12.271-beta (2026-07-17) - runtime-check module boundary (#2) [tooling]

- Moved the runtime regression and verification catalogue behind one explicit installer while preserving check order and command ownership.
- Reduced the entry point below its frozen size ceiling without changing the public beta feature surface.
- Added parity and module-boundary tests shared with the friends-only development stream.

## 0.12.270-beta (2026-07-17) - #664 Executioner's Sword light headshots [verify-fix]

- Added the default-off **Executioner's Sword: +30% Light Headshot Damage** option under Weapon Tweaks. Every light sweep, including the push follow-up, deals exactly 1.30x its otherwise-final damage when VT2 classifies the hit zone as a headshot.
- Kept body hits, both heavy attacks, attack speed, stagger, cleave, critical chance, and armor interaction unchanged. The policy follows `two_handed_swords_executioner_template_1`, so every career using that effective template receives the same behavior.
- Cloned the shared light damage profile into `wt_executioner_light_headshot_130`; registration is unconditional and deterministic, while the action repoint remains live-toggle and peer-parity gated through #431. Disabling the option or losing WT peer parity restores the exact original profile pointers.
- Added offline coverage in `test_cwv_axe_balance.lua` plus `/wt_regression_test` check `issue664_executioner_light_headshot_boundary` for exact 1.30x headshots, body/heavy isolation, every-light scope, registration/fallback, parity hold, idempotence, and exact restoration.

**Verification (in-game):** Enable the option, use an Executioner's Sword light chain against a repeatable enemy/dummy headshot and body-shot control, then disable it and repeat. Every light headshot should be exactly 30% higher; body hits and both heavies must match the disabled result. Run `/wt_regression_test` and expect `issue664_executioner_light_headshot_boundary` PASS.

## 0.12.269-beta (2026-07-17) - #611 [verify-fix] gear-style availability masters

- Replaced each career/slot's flat source-character master plus duplicated weapon rows with the established advanced-options pattern: the visible master checkbox selects or clears the whole source set, and its gear opens the exact individual weapon choices.
- Manual child choices remain independent. A partial selection keeps those weapons enabled while the derived master stays off; selecting the final child turns the master on, and clearing any child turns it back off without touching its siblings.
- Preserved per-career scope, melee/ranged separation, Kruber/Bardin/Kerillian/Saltzpyre/Sienna order, bounded cascade/repaint, and unknown future widget rows.
- Added an explicit master-to-widget-child contract to `/wt_regression_test`; offline coverage rejects flat duplication, missing advanced children, cross-career writes, and partial-selection churn.

**Solo verification:** Open Mod Tweaker > Weapons > Weapon Availability, then one career's Melee or Ranged group. Confirm only the source-character master rows are shown and each has a gear. Toggle a master on/off and confirm all children change. Open its gear, enable only some weapons, return, and confirm the selected weapons remain on while the master remains off. Enable the last child and confirm the master becomes on. Run `/wt_regression_test` and require `PASS: issue611_master_toggle_wiring`.

## 0.12.268-beta (2026-07-16) - weapon-bound career ability integration [verify-fix]

- Replaced first-row-only career-action injection with the same engine-free
  provider-neutral integration used by Weapons of Chaos. Vanilla iterates every
  `activated_ability` row against the currently wielded template; WT now does
  the same for enabled native cross-character ports and live CWV templates.
- Covered the complete current matrix: Ranger Veteran, Waywatcher (both normal
  and piercing rows), Bounty Hunter, Pyromancer, Grail Knight, Outcast
  Engineer, Sister of the Thorn, Warrior Priest, and Necromancer.
- Preserved exact cleanup ownership: WT records and removes only rows it added;
  an action already authored by a donor template is never removed. Missing
  career settings or action templates emit one bounded integration error.
- Added executable shared-helper tests for all ten actions, alternate rows,
  existing-row identity, and incomplete providers. In-game confirmation remains
  required; this change is not shipped by this commit.

## 0.12.267-beta (2026-07-16) - #611 [verify-fix] per-career master scope

- Moved every Weapon Availability master inside an individual receiving career's Melee or Ranged subgroup. A master now changes only that career, never the other careers of the same character.
- Fixed the source order to Kruber, Bardin, Kerillian, Saltzpyre, Sienna in every career/slot leaf. Missing source buckets are omitted without disturbing the remaining order.
- Preserved targeted derived state: changing one weapon recomputes only its corresponding career/slot/source master. Turning a master on or off still cascades only its bounded child set.
- Styled master labels with GUI Tweaker's established `font_button_normal` warm-tan color through VMF's proven checkbox-widget factory; ordinary weapon rows remain white.
- Expanded `/wt_regression_test` check `issue611_master_toggle_wiring` and added offline `test_wt_master_toggles.lua` coverage for career isolation, source order, targeted child recompute, master cascade, seeding, and style-hook wiring.

**Verification (in-game):**
1. Open Weapon Availability > Kruber > Melee > Mercenary. Confirm the masters are inside Mercenary and ordered Kruber, Bardin, Kerillian, Saltzpyre, Sienna (omitting any empty source), with warm-tan labels.
2. Turn on Mercenary's **Enable All Kerillian Melee Weapons**. Confirm only Kerillian-labelled rows in Mercenary change; Huntsman, Foot Knight, and Grail Knight remain unchanged.
3. Turn one covered Mercenary weapon off. Confirm only Mercenary's Kerillian master turns off and every unrelated master retains its state.
4. Repeat in one Ranged career subgroup, reopen the menu, and run `/wt_regression_test`; expect `issue611_master_toggle_wiring` PASS.

## 0.12.266-beta (2026-07-16) - issue 611 Weapon Availability master toggles

- Added "Enable All &lt;Character&gt; Melee/Ranged Weapons" master toggles to Weapon Availability. Each receiving character's Melee and Ranged group now starts with one master per source character that contributes weapons, so a whole source character's melee or ranged set can be turned on or off in a single click.
- Turning a master ON enables every availability toggle it covers; turning it OFF disables them all. Deselecting any single covered weapon flips its master back to OFF automatically while leaving the other weapons as they are (issue 611 behavior).
- Source character is read from each weapon's display label, not its internal key, so ports whose owner differs from the key prefix (for example the Flail shown as "Saltzpyre: Flail") group under the character the player actually sees.
- Masters cover exactly the weapons visible beneath them: the child sets are built after the alphabetical sort and the Career Weapon Variants strip, so a master never claims a hidden row and the auto-off math stays exact. Each master's checkbox is reconciled to its children at load, so saved availability choices render a truthful master state.
- Added `/wt_regression_test` check `issue611_master_toggle_wiring` covering the master/children maps, the child-to-master reverse index, per-child source-label grouping, and localization ownership.

**Verification (in-game):**
1. Enable Tweaker: Weapons (and VMF). Open the F4 mod options, then Tweaker: Weapons, then Weapon Availability, then Bardin, then Melee.
2. Confirm the group starts with master rows such as "Enable All Kruber Melee Weapons", "Enable All Kerillian Melee Weapons", "Enable All Saltzpyre Melee Weapons", "Enable All Sienna Melee Weapons" above the per-career subgroups.
3. Check "Enable All Kerillian Melee Weapons". Confirm every Kerillian-labelled melee weapon under each Bardin career subgroup becomes checked in the same frame.
4. Uncheck one of those Kerillian melee weapons (for example "Kerillian: Glaive"). Confirm the master flips to OFF while the other Kerillian melee weapons stay checked.
5. Re-check every Kerillian melee weapon by hand and confirm the master flips back to ON on the last one.
6. Uncheck "Enable All Kerillian Melee Weapons" and confirm all its covered weapons clear.
7. Reopen the menu (or restart) and confirm the master states match their weapons (a master reads ON only when all its weapons are ON). Enter a mission on a Bardin career and confirm the enabled cross-character weapons are wieldable and the disabled ones are not.

## 0.12.265-beta (2026-07-15) - #635 public beta surface cleanup

- Removed the live 3P Animation Picker and Hold-Pose tuner modules, widgets, handlers, commands, dynamic status decoration, and tuning-only diagnostics from the public beta. They remain available in the separate friends-only `wt_dev` stream.
- Preserved every baked animation remap, grip/scale/rotation transform, cross-career availability control, weapon tweak, and read-only support command owned by the public mod.
- Removed the bounded #290 Billhook and #316 Longbow live probes from the public runtime; their evidence owners and offline probe test now live only in the friends-only development stream.
- Extended `qa/check_wt_stream_parity.ps1` to reject public dev-tool files/symbols/status tags, issue-specific live probes, non-read-only commands, and orphan visible settings. Every accepted stream difference is now enclosed by a uniquely paired overlay marker; the old whole-file exemptions are gone.
- Added `/wt_regression_test` check `issue635_public_beta_dev_surface_absent` for the public runtime export boundary.
- Removed the retired Kruber Longbow zoom-controls claim from the Workshop feature list; the native draw behavior remains owned by the shipped #316 animation fix, not a user-facing zoom setting.

## 0.12.264-beta (2026-07-15) - #316 Kruber Longbow native draw playback [verify-fix; coop-required]

- Fixed the live-evidence regression where Mercenary successfully entered
  `ActionAim` zoom but WT replaced `draw_bow` with the generic `to_zoom` body
  event, suppressing the visible bow draw. Mercenary, Foot Knight, and Grail
  Knight now explicitly preserve Kruber's native `draw_bow` event; Huntsman is
  unchanged as the native control.
- Kept Saltzpyre's Longbow-to-Crossbow presentation substitution intact,
  including its `draw_bow -> to_zoom` and firing-event translations. The
  first-person unit still bypasses WT's 3P funnel entirely.
- Applied the same policy through the existing per-unit animation funnel used
  by both the local owner body and remote husks. No per-frame work, new RPC, or
  shared-template mutation was added.
- Corrected #316's bounded diagnostic language: a successful camera/status zoom
  now reports `camera_zoomed` with `visible_draw=unverified`, so zoom state can
  never again be mistaken for proof that a body clip visibly played.
- Moved **Enable Hold-Pose Tuner** to the first row inside its group, before the
  target controls and First/Third Person collapsibles. Its tooltip now states
  that OFF bypasses all position, rotation, and scale changes while preserving
  every saved value; bypass semantics and defaults are unchanged.
- Added offline and runtime coverage for all three Kruber careers, native
  Huntsman isolation, Saltzpyre preservation, owner/husk state seams,
  first-person exclusion, non-overclaiming diagnostics, and tuner control order.

**Co-op verify:** As Mercenary, Foot Knight, and Grail Knight, equip Kruber's
Longbow, hold aim through zoom, and confirm the visible draw/aim pose both on
the owner's local third-person body and from the other player's view. Repeat on
Huntsman as the unchanged native control. Then equip the same Longbow on a
non-Priest Saltzpyre career and confirm its Crossbow model/animations still
work. First-person aim/zoom must remain unchanged. The log should show
`[wt:316] ... remap=native_draw_bow` and camera results with
`visible_draw=unverified`.

## 0.12.263-beta (2026-07-15) - #616 Hold-Pose third-person live delivery [verify-fix]

- Fixed the setting callback boundary that saved third-person position, rotation, and scale edits without applying them. Active-channel edits now perform one immediate one-shot write, including in keep screens where the mission update hook may not run.
- Kept the master and per-channel bypasses non-destructive. An edit made while bypassed remains saved and emits one bounded `saved_not_applied` diagnostic explaining the master/channel state; it does not silently defeat the off toggle.
- Grouped all existing third-person controls beneath a **Third Person** collapsible parallel to **First Person**, without changing setting IDs or persisted values.
- Added offline and runtime regression coverage for exact 1P/3P dispatch, immediate delivery, bypass semantics, and the collapsible hierarchy.

Enable the Hold-Pose master and Third Person channel, wield a weapon in the keep, then change one offset, one rotation, and one scale value. Each must move immediately and the log must report `[wt:616] tuner edit delivered ... channel=third_person`. Turn the master off and edit again: the pose must remain canonical and the log must report `saved_not_applied`; turn it back on and confirm the saved values return. Run `/wt_regression_test` and confirm `issue616_hold_pose_live_edit_delivery` passes.

## 0.12.262-beta (2026-07-15) - public beta rollup

- Cut the current active Tweaker: Weapons line as a public beta. This is a release-track promotion of the already-built, committed, and uploaded `0.12.261-dev` payload; it does not introduce another gameplay change between the final dev candidate and this beta.
- Included the current working line: CWV Combat Style ownership/default integration (#620); opt-in 1H Axe, Cog Hammer, and Mace and Sword balance controls (#621/#622/#623); isolated first-/third-person Hold-Pose channels and scale/bypass controls (#616); Crowbill and Ranger preview-idle corrections (#603/#606); current CWV ownership, availability, identity, appearance-transform, animation, and weapon-tweak integrations documented in the entries below.
- Preserved public defaults: every new balance nerf remains default-off; the Hold-Pose tuner master remains default-off; CWV-dependent defaults remain conditional on CWV readiness and preserve user overrides.
- Excluded the abandoned `weapon_tweaker_dev` experiment clone in full. It is a stale 0.12.139-dev fork, not the development source for this mod, and copying it would regress the active line. Open-issue diagnostics and explicitly requested developer tuning controls already belonging to the single active stream remain bounded behind their existing gates.

Run `/wt_regression_test`, then walk the verification steps attached to the open Tweaker: Weapons issues. This beta changes only the release suffix from the already-shipped 0.12.261-dev candidate, so its behavior should be byte-equivalent apart from version/reporting metadata.

## 0.12.261-dev (2026-07-15) - #620 CWV Tuskgor Combat Style default [verify-fix; coop-required]

- Kept WT-alone Foot Knight Tuskgor Spear default-off. When active CWV positively marks the native Tuskgor Combat Style family ready, WT seeds that exact Foot Knight setting on once per profile; late load and hot reload converge without repeatedly overriding later user choices.
- The normal WT setting remains the final control after its one-time default seed. No hard dependency, per-frame check, item grant, or new transport was added.
- Removed the retired standalone Infantry Spear, Imperial Longsword, and Black Guard Blade from WT's CWV availability catalogue. Their canonical native items now own those Combat Styles, so WT cannot re-expose duplicate craft families.
- Added offline readiness/load-order/one-shot coverage and runtime `issue620_cwv_tuskgor_foot_knight_default`.

With CWV v0.1.422-dev active, confirm Foot Knight's Tuskgor row defaults on and the live item is wieldable. Turn it off manually, transition, and confirm it stays off. On a fresh WT-only profile it must remain off. Enable/hot-reload CWV and confirm the one-time default converges on after its style marker becomes ready.

## 0.12.260-dev (2026-07-15) - #621 #622 #623 opt-in weapon balance nerfs [verify-fix]

- Added default-off **1H Axe: 10% Less Cleave**. WT discovers donor-faithful single-axe templates by their combat capability, not labels, and redirects only direct attacks to private 0.90x attack/impact-cleave profiles. Dual Axes, Axe and Shield, throwing axes, 2H axes, shared profiles, and shared power rows remain unchanged.
- Added default-off **Cog Hammer: 10% Slower Heavies**. Only the four axe/charged-mode heavy releases take 10% longer; lights, wind-ups, push, block, wield, and weapon special retain authored timing.
- Added default-off **Mace and Sword: Slower Attacks**. Only vanilla Mace and Sword light 1/light 2 and both heavy releases take 10% longer. Later lights, push, utility actions, and CWV's reversed Sword and Mace template are excluded.
- All three settings hot-apply and exactly restore captured values. The 1H Axe profile repoint composes with WT's existing custom-profile peer-parity gate and wire floor; profile registration is deterministic and preference-independent.
- Added offline and `/wt_regression_test` coverage for capability boundaries, exact multipliers, shared-table preservation, action allow-lists, idempotence, restoration, and parity fallback.

Enable and disable each toggle separately in a keep or mission. For 1H Axe, compare a single axe with Dual Axes and Axe and Shield. For Cog Hammer, test both mode families plus light/push controls. For native Mace and Sword, compare L1/L2 and heavies with later lights and CWV Sword and Mace. Run `/wt_regression_test`; all three issue checks must pass.

## 0.12.259-dev (2026-07-14) - #616 isolated 1P/3P Hold-Pose tuning and bypass [verify-fix]

- Added a distinct first-person Hold-Pose channel with independent right/left offset, Euler rotation, and absolute non-uniform scale. It resolves only the local player's 1P wield units; the existing channel resolves only local-owner 3P units.
- Added a simple master **Enable Weapon Hold-Pose Tuner** switch plus independent **Enable first-person tuner** and **Enable third-person tuner** switches. The master defaults off. Disabling the master restores both views; disabling a channel restores only that view. Neither path zeros or erases slider values, and re-enabling resumes with the saved values.
- Kept the tuner out of inventory/hero previews, bots, remote husks, score presentation, and committed transforms. Dump now emits separate first- and third-person tables, including bypassed values.
- Extended the offline Lua and in-game runtime suites for channel isolation, component composition, saved-value persistence, bypass/restore behavior, and excluded-surface ownership.

Enable the master and Live re-apply, tune a visible 3P value and a visible 1P value, then disable the master. Both views must immediately return to their baked poses without any numeric field changing; re-enable the master and confirm both prior values return. The per-channel switches must bypass only their own view.

## 0.12.258-dev (2026-07-14) - #616 complete Hold-Pose transforms [verify-fix]

- Added independent right/left Scale X, Y, and Z controls to the dev Weapon Hold-Pose tuner. Identity is `{1, 1, 1}`; values are absolute, non-uniform, and reconstructed every apply so live re-apply cannot compound.
- Scale uses its own `Unit.set_local_scale` write and composes with the existing canonical-plus-delta position/rotation paths without clobbering either. Reset restores the captured baked scale, and the dump now emits all nine transform values per hand.
- Added runtime regression coverage for identity, non-uniform scale, complete transform composition, and the explicit absolute/non-compounding contract.

Open Dev: Weapon Hold Pose Tuner, confirm Scale X/Y/Z appear under both hands, change one axis with live apply enabled, and verify offset/rotation remain intact. Run `/wt_dev_hp_reset` and confirm the weapon returns to its baked scale; `/wt_dump_hold_pose` must include `scale = { x, y, z }`.

## 0.12.257-dev (2026-07-14) - Crowbill and Ranger preview idles [verify-fix]

- **Crowbill inventory preview:** Added receiver-side `to_1h_sword` wield entries for every Bardin and standard Saltzpyre career, matching the existing Kruber/Kerillian correction. The original Sienna `bw_1h_crowbill` remains independently available in WT and is never yielded to CWV's Imperial/Dawi Crowbill families; its vanilla fire-DoT attack identity is unchanged.
- **#603 failed verification:** Ranger Veteran Dual Axes now use the known-good non-Slayer `to_dual_hammers` stance only on the inventory-screen character preview. The prior candidate merely re-fired `to_dual_axes`, which the current user check identified as the Slayer-style preview pose. Dual Hammers, Slayer, owner/remote mission 3P, and 1P remain untouched.
- **Regression:** Added engine-free ownership/preview assertions plus runtime checks for all eleven non-Sienna Crowbill receivers and the exact Ranger/Axes preview correction with Dual Hammers and Slayer controls.

Open Bardin's inventory character preview with Sienna's original Crowbill and confirm the one-handed idle is restored. Separately, preview Dual Axes on Ranger Veteran and confirm the pose matches the subtle non-Slayer dual-wield family rather than Slayer's stance; Dual Hammers must remain unchanged.

## 0.12.256-dev (2026-07-14) - #604 Crowbill catalog and #597 Greataxe ownership [verify-fix; coop-required]

- Added the CWV Imperial and Dawi Crowbill families to WT's bounded career catalog so their authored owners remain default-on and every optional receiver remains independently controllable.
- With CWV active and its replacement ready, Kruber and Saltzpyre use CWV's Kruber Greataxe instead of Bardin's native Greataxe. WT preserves saved native values but cedes menu, runtime, cache, and final-write ownership; the Bardin fallback returns when CWV is absent or not ready.
- Hardened the existing Axe+Shield handoff so WT yields the native fallback only after both exact CWV replacements are registered, preventing load-order gaps.

### Co-op verification

With CWV active, confirm Kruber and Saltzpyre receive the CWV Kruber Greataxe and never Bardin's Greataxe; Bardin remains unchanged. Confirm the Crowbill career controls, then have both peers inspect the selected models and mode. Disable CWV and confirm WT restores native fallback availability without losing saved settings.

## 0.12.255-dev (2026-07-14) - #603 Ranger Veteran Dual Axes inventory idle [verify-fix]

- The native diagnostic proved Ranger Veteran Dual Axes selected the correct `to_dual_axes` event, but the inventory-screen character preview lost that pose after unit spawn/link.
- Reasserted the same native event once after preview spawn only for the exact Ranger Veteran + Dual Axes combination. Known-good Dual Hammers, Slayer, first person, and every mission animation path remain untouched.
- Expanded the repository appearance standard: every third-person model, transform, and pose change must explicitly cover the inventory-screen character preview alongside owner 3P, bots, remote husks, lobby, score/team, and other preview cells.

### Solo verification

On Ranger Veteran, open the inventory-screen character preview with Dual Axes and compare it with known-good Dual Hammers. Dual Axes must retain their distinct native idle after the preview finishes loading; Dual Hammers and Slayer must remain unchanged.

## 0.12.255-dev (2026-07-14) - #601 axe identity ownership and #593 menu reconciliation [verify-fix]

- Moved the three default-on Greataxe/Dual Axes balance controls into Weapon Tweaks. Native weapons work with WT alone; the optional CWV Kruber Greataxe is discovered after its late template registration without creating a hard dependency.
- With CWV active, the frozen WT menu tree now removes Bardin Axe+Shield fallback rows for Kruber and standard Saltzpyre while retaining their saved values. Runtime reconciliation also observes when both CWV Empire variants become ready, preventing load-order and cache final-write drift.

### Solo verification

Confirm the three axe balance toggles appear under Weapon Tweaks and work with WT alone; with CWV installed, its Greataxe joins the same policy. On Witch Hunter Captain with CWV active, Bardin Axe & Shield must be absent and the CWV Empire/Kruber Axe & Shield option must be present. Disable/re-enable CWV and confirm ownership reconciles without duplicate or stale rows.

## 0.12.254-dev (2026-07-14) - #602 Dawi Mace family availability [verify-fix; coop-required]

- Added all three CWV Dawi Mace variants to WT's bounded career catalog. Their source-backed Bardin careers keep the CWV defaults; every other career is exposed as an independent default-off option.
- Catalog tests now derive their bounds from the declared rows and verify every authored/default/conditional career split rather than relying on stale hard-coded totals.

### Co-op verification

With CWV `0.1.411-dev`, confirm all three Dawi variants appear for their default Bardin careers and that WT can independently disable those defaults or enable another career. Verify a second player sees the same equipped variant after transitions.

## 0.12.254-dev (2026-07-14) - #603 Ranger Veteran dual-hammer inventory idle [diagnostics-armed]

- Added a bounded diagnostic at the existing inventory-preview wield boundary. For Ranger Veteran Dual Hammers and Dual Axes it records the resolved wield event and whether the preview body contains that event plus the two distinct vanilla family events, without changing the pose.

### Diagnostic capture

Open Ranger Veteran's inventory preview with Dual Hammers, then Dual Axes. The newest log should contain one `[wt:603]` row per distinct weapon/event; attach those rows to #603 so the correct native idle can be selected without guessing.

## 0.12.253-dev (2026-07-14) - #597 #576 Greataxe availability and Axe+Shield Heavy 3 [verify-fix; coop-required]

- Replaced the retired CWV Poleaxe row with the Kruber Greataxe. All four Kruber careers default on; every other supported career is an independent default-off WT opt-in. Disable/removal restores only CWV's authored owners.
- Corrected Axe+Shield's three-heavy donor chain over Saltzpyre's two-heavy Axe+Falchion vocabulary: H1 maps to target H1, H2 to target H2, and H3 commits through the target-H1 cycle restart. Diagnostics now distinguish Heavy 3 wind-up from the committed release, so a charge-only false positive cannot pass.

### Co-op verification

Confirm Greataxe career toggles and per-model transform tuning. On Axe+Shield, perform H1, H2, and H3 repeatedly while a second player observes; both owner 3P and remote husk must show every charge and release. With the dev picker enabled, require separate `[wt:576]` phases for `h3_charge` and `h3_committed_attack`. Run `/wt_regression_test`.

## 0.12.252-dev (2026-07-14) - #596 Infantry Spear availability [verify-fix; coop-required]

- Added CWV Infantry Spear to WT's bounded availability catalog. Mercenary, Huntsman, and Foot Knight are default-on and independently disableable; Grail Knight and all other careers are exposed default-off.
- WT removes only its 17 optional receivers when CWV/WT is disabled and restores the three CWV-authored careers. Every enabled receiver receives its career-ability action on the live custom template.
- Extended the pure availability policy and offline tests for per-career defaults, all 20 careers, Grail Knight opt-in, lifecycle restoration, and the 30-item CWV catalog.

## 0.12.251-dev (2026-07-14) - #112 tune Saltzpyre Kruber shield rotation [verify-fix; coop-required]

- Baked the requested local Euler correction `{X=25, Y=-17.5, Z=-15}` for Empire Mace & Shield, Empire Sword & Shield, Bretonnian Sword & Shield, and the CWV Empire Axe & Shield family on Witch Hunter Captain, Bounty Hunter, and Zealot. These are the Kruber-derived shield ports currently seated on Saltzpyre's Axe+Falchion third-person vocabulary.
- Explicitly excluded Kruber Spear & Shield (`es_deus_01`), Warrior Priest, and native Kruber renderers. The live CWV clone-name boundary is covered through `dr_shield_axe`, while both intended `cwv_es_axe_shield` identities are also catalogued so a future identity repair does not silently lose the correction.
- Generalized the existing durable #569 orientation owner to compose either its canonical WP-remap half-turn or a keyed Euler delta over the captured canonical rotation. Owner, bot, remote-husk, and inventory-preview 3P roots consume the same shipped transform; first person is never written, rotations are reconstructed without accumulation, and no RPC or per-frame payload was added.
- Added offline and `/wt_regression_test` coverage for the exact triplet, every standard Saltzpyre career, all intended shield keys, Spear & Shield exclusion, native Kruber/Warrior Priest controls, clone-name compatibility, and transform ownership scope.

### Co-op verify

On Witch Hunter Captain, Bounty Hunter, or Zealot, equip Empire Mace & Shield, Empire Sword & Shield, Bretonnian Sword & Shield, then CWV Empire Axe & Shield. Inspect each in third person through wield, block, attack, swap away/back, and inventory preview; each should retain the new seating. A second player must confirm the same seating on the remote husk after spawn and weapon swaps. Kruber Spear & Shield must remain unchanged. Run `/wt_regression_test` and require `issue112_saltzpyre_kruber_shield_baked_rotation` to pass.

## 0.12.250-dev (2026-07-14) - #593 extend Axe+Shield CWV handoff to Saltzpyre [verify-fix]

- Extended the existing reversible Axe+Shield ownership boundary from Kruber to Witch Hunter Captain, Bounty Hunter, and Zealot. With CWV active, WT no longer offers Bardin's native `dr_shield_axe` to those careers; with CWV absent or disabled, their saved WT native toggle remains the fallback.
- Added the Empire CWV family (`cwv_es_axe_shield` and `cwv_es_axe_shield_veteran`) to WT's availability surface for the three standard Saltzpyre careers. The variants retain their canonical CWV identity, cosmetics, and base moveset instead of masquerading as Bardin's native item. Warrior Priest is deliberately excluded because the existing Saltzpyre shield-port routing covers only the standard body.
- Added explicit conditional-career metadata so disabling/hot-reloading CWV or disabling WT removes only WT's three cross-receiver additions. CWV's four authored Kruber owners are untouched. The existing active-state transition reconciles `can_wield` and rejects stale cached native loadouts without a restart. WT also injects each receiving Saltzpyre career's activated-ability action into the live variant template, so a default-on CWV child does not depend on the donor fallback checkbox being enabled.
- Expanded offline and runtime regression coverage for all seven handoff receivers, both Empire variants, active/inactive transitions, exact settings composition, and the Warrior Priest/native Bardin boundaries.

### Solo verify

On WHC, Bounty Hunter, or Zealot with CWV inactive, enable WT's Bardin Axe+Shield fallback and confirm it appears. Enable CWV: the Bardin item must disappear and both Empire CWV Axe+Shield variants must be available. Disable CWV again: the Empire variants must disappear and the saved Bardin fallback must return. Run `/wt_regression_test` and require `issue593_conditional_cwv_axe_shield_ownership` to pass.

## 0.12.249-dev (2026-07-14) - #112 restore Saltzpyre Handgun grip offset [verify-fix]

- Restored the user-tuned Empire Handgun third-person position on standard Saltzpyre careers: local Y `-0.17`, local Z `-0.05`, and unchanged X. The prior v0.12.135 correction was removed in v0.12.136 because it mutated a shared attachment-linking table; its intended receiver-scoped replacement had never been added to the canonical baked offset table.
- Added `es_handgun.wh_ = {0, -0.17, -0.05}` to `_weapon_grip_offsets` and the durable reapply set. Captain, Bounty Hunter, and Zealot consume the correction; native Kruber careers do not. The existing owner/bot/husk tracker reconstructs canonical position plus the delta every frame, so animation ticks cannot erase it and repeated frames cannot compound it.
- Position, rotation, and scale remain separate transform components. This change never writes first-person units, never resets #569 rotation or scale, never mutates a shared weapon template, and adds no RPC or per-frame network traffic.
- Added offline and `/wt_regression_test` coverage for the exact axes, durable membership, all standard Saltzpyre careers, native Kruber exclusion, and an unmodified ranged control.

### Solo verify

On Witch Hunter Captain, Bounty Hunter, or Zealot, equip Kruber's Empire Handgun and inspect it in third person. Wield, fire, swap away, and swap back; the model should retain the corrected Y/Z seating without moving first person. Run `/wt_regression_test` and require `issue112_saltzpyre_handgun_baked_offset` to pass.

## 0.12.248-dev (2026-07-14) - #113 Warrior Priest 3P coverage reconciliation [verify-fix]

- Reconciled Warrior Priest as its own receiver: the live catalog is exactly seven melee weapons, comprising six native `wh_*` entries and one cross-character port (`es_1h_flail`). The cross-character census is 1 working, 0 pending, 0 untested, 0 offsets, and 0 picker-visible.
- Added the missing dev-only presentation for Empire Flail's shipped Warrior Priest event map. This describes the existing per-unit flail correction without inventing a whole-weapon model or animation substitute.
- Added a bounded closed-catalog startup census and `/wt_audit_warrior_priest_3p`. It reports unexpected or missing entries so a future ranged or ordinary-Saltzpyre availability leak is immediately visible; it does not mutate the catalog.
- Added a current audit ledger and offline regression coverage for the exact seven-key melee allow-list, six/native-one/cross split, working status, target/model honesty, absent picker membership, and diagnostic wiring.

### Solo verify

Start once with WT enabled and require `[wt:113] Warrior Priest catalog=7 native=6 cross=1 working=1 needs_anims=0 picker=0 unexpected=0 missing=0` in the log. In dev Weapon Availability, Empire Flail must read `[working → Warrior Priest flail event map]`; no ranged or unexpected row may appear. `/wt_audit_warrior_priest_3p` logs the single cross-character row. No co-op session is required because this pass changes coverage classification/presentation diagnostics only.

## 0.12.247-dev (2026-07-14) - #112 Saltzpyre non-WP 3P coverage reconciliation [diagnostics-armed]

- Reconciled `wh_captain`, `wh_bountyhunter`, and `wh_zealot` against the live unlock source. Each now has the same 54 distinct cross-character ports (17 Kruber, 10 Bardin, 15 Kerillian, 12 Sienna), not the issue's stale 61-row snapshot.
- Corrected Empire Mace, Empire Sword, and Kerillian 1H Axe from the generic pending fallback to `[working]`, matching the documented universal/native 1H event-family behavior and the explicit Saltzpyre axe wield route.
- Removed the unreachable Bardin Dual Hammers status declaration. That native Bardin item is no longer offered on non-WP Saltzpyre and had no live picker catalog, so retaining it advertised a tuning path the player could not enter.
- Added honest dev annotations for 13 still-pending source/coverage-backed targets without promoting them or manufacturing empty picker controls. Reaper and Elf Spear remain the only two picker-visible rows; Shortbow and Hagbane remain pending with no shipped target/model substitute.
- Added one bounded three-career parity census, `/wt_audit_saltzpyre_3p`, a current audit ledger, and offline regression coverage for exact counts, parity, classifications, target honesty, stale-row absence, and diagnostics wiring.

### Diagnostic capture

Start once with WT enabled and require `[wt:112] Saltzpyre non-WP careers=3 parity=true ports=54 working=37 needs_anims=17 untested=0 picker=2 hidden_needs_anims=15 targets=15 no_target=2` in the log. Run `/wt_audit_saltzpyre_3p` for the bounded 17-row unresolved list. Target labels are routing evidence, not visual-playback proof.

## 0.12.246-dev (2026-07-14) - #111 Kerillian 3P coverage reconciliation [diagnostics-armed]

- Reconciled all four Kerillian careers against the live unlock source: each has 60 cross-character ports, currently split into 44 working, 14 needing animations, and 2 genuinely untested. The issue's old 11-confirmed snapshot predates the 33-port picker bake and subsequent confirmed rows.
- Corrected the two coverage gaps (`es_1h_mace`, `es_longbow`) from the generic `[needs animations]` fallback to `[untested]`; no receiver target is documented for either, so implying a decision would be false.
- Added source-backed dev annotations for the 14 remaining ranged ports whose coverage target is the Elf Repeater Crossbow. The labels do not promote those ports or expose empty picker controls: all 14 still lack a baked per-attack map and matching static picker catalog.
- Added one bounded startup census, `/wt_audit_kerillian_3p`, an updated coverage ledger, a detailed audit/migration queue, and offline regression coverage for exact career parity, status counts, known/unknown target honesty, and diagnostic wiring.

### Diagnostic capture

Start once with WT enabled and require `[wt:111] Kerillian 3P ports=60 working=44 needs_anims=14 untested=2 picker=0 hidden_needs_anims=14` in the log. Run `/wt_audit_kerillian_3p` for the bounded unresolved-row list. Do not infer visual success from a target label; the 14 ranged rows still require static picker vocabularies, tuning, and baking.

## 0.12.245-dev (2026-07-14) - #110 Bardin 3P coverage reconciliation [verify-fix]

- Reconciled all four Bardin careers against the live unlock source: each has exactly five cross-character ports, and source/coverage proves all five working. Empire Handgun now follows its documented Bardin-native `to_handgun` classification instead of falling through to `[needs animations]` merely because its item key has an `es_` prefix.
- Added honest dev-only annotations for the four melee ports. They identify a Bardin-scoped 1H event map rather than inventing a whole-weapon substitute that the source does not establish. Empire Handgun stays plain `[working]`; Bardin has no model substitutes.
- Added one bounded startup census and `/wt_audit_bardin_3p` for the full five-row log record. The audit is read-only and does not mutate animation templates, unlocks, settings, or network state.
- Added offline regression coverage for career parity, the five-working status contract, display annotations, absent model substitutions, and diagnostic wiring.

### Solo verify

Open dev Weapon Availability for each Bardin career. Elf Sword, Empire Sword, Falchion, and Crowbill must show `[working → Bardin 1H event map]`; Empire Handgun must show plain `[working]`. Run `/wt_audit_bardin_3p` and require `ports=5 working=5 needs_anims=0 untested=0 picker=0` in the log. No co-op session is required because this pass changes status/display diagnostics only.

## 0.12.244-dev (2026-07-14) - #109 Kruber 3P coverage drift audit [diagnostics-armed]

- Reconciled the tracker against the live unlock source: all four Kruber careers now share 52 cross-character ports, split into 37 working, 13 needing animations, and 2 untested. Since the previous 51-row snapshot, native Bardin Dual Axes was removed while Saltzpyre Crossbow and the independently WT-owned Axe & Falchion became live rows.
- Documented Moonfire Bow's source-backed Empire Longbow wield target without falsely promoting its unbaked per-attack behavior to working. Known pending targets now remain visible in dev availability labels while unknown decisions stay blank.
- Added a bounded, read-only startup log summary and `/wt_audit_kruber_3p` detail command. The report calls out all 13 needs-animation rows hidden from the static picker; they are not force-added until matching template/attack vocabularies exist.
- Added offline coverage for exact career parity, the 52-row/status contract, honest known/unknown targets, and diagnostic wiring.

### Diagnostic capture

Start once with Weapon Tweaker enabled; the log should contain `[wt:109] Kruber 3P ports=52 working=37 needs_anims=13 untested=2 picker=0 hidden_needs_anims=13`. Run `/wt_audit_kruber_3p` for the bounded per-row list. This is a source/coverage diagnostic; do not infer visual success from a target name.

## 0.12.243-dev (2026-07-14) - #108 dev availability labels expose 3P redirects and model substitutes [verify-fix]

- Dev-build Weapon Availability tags now retain the borrowed 3P animation vocabulary after a port becomes confirmed/baked instead of showing only `[working]`. The display-only mirror covers the confirmed Kruber, Kerillian, and Saltzpyre picker-bake batches without changing their status or runtime remap tables.
- Added the shipped model-substitution labels for Kruber's Brace/Repeating Pistols (`Repeater Handgun`) and Saltzpyre's Kruber/Elf/Moonfire longbows (`Crossbow`). The annotation describes third-person and preview rendering only; first-person models remain unchanged.
- Centralized composition in pure `wt_port_status.decorate_tag`. A non-dev caller receives the original status tag byte-for-byte, while dev builds can show both concerns together (for example, `[working → Empire Greathammer]` or `[working - 3P model: Repeater Handgun]`).

### Solo verify

Open Weapon Availability in this `-dev` build. On Kruber, Glaive must show `→ Empire Greathammer`, the three Elf duals must show `→ Empire Mace & Sword`, and Brace/Repeating Pistols must show `3P model: Repeater Handgun`. On Saltzpyre, Kruber Longbow, Elf Longbow, and Moonfire Bow must show `3P model: Crossbow`. Ordinary native rows must retain a plain `[working]` tag. Run the standalone Lua policy test and require all #108 cases to pass.

## 0.12.242-dev (2026-07-14) - #391 per-career CWV availability [not deployed]

- Expanded #368's bounded 29-item CWV availability catalog from one all-careers switch per variant to one backward-compatible item master with four independent authored-career children. Existing `unlock_cwv_variant_<item>` values retain their meaning; a saved false still disables that entire item, while each career now has its own default-on `unlock_cwv_variant_<career>_<item>` choice.
- The final `can_wield` reconciliation now composes the item master and exact career choice before replacing only that career's membership. It still requires the live `ItemMasterList` entry's positive `cwv_variant == true` marker and performs no hooks, RPCs, per-frame work, or writes outside CWV's authored receiver list.
- Source confirmation resolved the issue's gating question: CWV copies each definition's `careers` array directly into the clone's `can_wield`; vanilla's backend wield and inventory-filter functions test membership in that array (`character_weapon_variants.lua:9769-9771`; decompile `backend_interface_common.lua:15-24,93-111`). Foot Knight has no separate item gate. Grail Knight and Warrior Priest remain subject to owning/selecting those careers, not a CWV item restriction.
- Added pure Lua schema/decision coverage and runtime regression check `issue391_cwv_per_career_availability`. Repository verification requires 29 compatible masters, 116 unique career children, exact composition behavior, positive-marker gating, and live Dual Axes reconciliation.

### Solo verify

With CWV active, open Weapon Availability -> Career Weapon Variants. Expand Kruber Dual Axes and independently disable Foot Knight while leaving Mercenary, Huntsman, and Grail Knight enabled. Transition keep-to-mission and back: only Foot Knight must lose the CWV item. Re-enable Foot Knight, disable the Kruber Dual Axes parent, and confirm all four Kruber careers lose it; re-enable the parent and confirm each saved child choice returns. Repeat the child-only check on Saltzpyre Dual Axes with Warrior Priest. Run `/wt_regression_test` and expect `issue391_cwv_per_career_availability` to pass.

## 0.12.241-dev (2026-07-14) - #433 remove dead Big Rebalance payload [not deployed]

- Deleted the unreachable Big Rebalance implementation and definitions (166,554 bytes total), its no-op lifecycle dispatch, and two regression checks that exercised formulas callable only from the retired hooks. Historical source remains recoverable from git.
- Preserved every active weapon-availability, animation, transform, backend, and trait-pool path. Existing saved `br_*` values remain untouched; the hidden identifier catalog and prefix stay reserved by the blocking retirement gate.
- Repository-only verification: retired-BR absence gate, WT lint, Lua tests, and Quick QA. No in-game behavior existed to verify.

## 0.12.240-dev (2026-07-14) - #368 independent WT/CWV availability [verify-fix]

- Removed the legacy `cwv_managed` cede path. Kruber's Saltzpyre Axe, Falchion, and Axe & Falchion are ordinary WT-owned rows; their fresh defaults follow CWV presence while persisted choices continue to win.
- Removed `wh_1h_axe` from the stale-removal tombstones that clobbered CWV every state transition. WT now performs one deferred next-frame reconciliation after state entry, making its enabled/disabled choice the final bounded `can_wield` write after CWV registration.
- Added a CWV availability group covering all 29 authored non-skin variant definitions. Runtime application enumerates the live `ItemMasterList` and only mutates entries positively marked `cwv_variant == true`; each toggle defaults on and controls the variant's authored receiver careers.
- Added offline coverage plus `/wt_regression_test` check `issue368_cwv_independent_availability` for cede removal, all twelve overlap rows/widgets, conditional defaults, marker gating, catalog bounds, and deferred final-write wiring.

### Solo verify

With CWV enabled, enter the keep and confirm the three Saltzpyre weapons remain available on each Kruber career and the Career Weapon Variants availability group defaults on. Disable one vanilla overlap and one CWV clone, transition keep-to-mission and back, and confirm only those choices remain unavailable. Re-enable them and confirm availability returns. Repeat once with CWV absent: the three cross-character WT rows must retain their standalone opt-in defaults.

## 0.12.239-dev (2026-07-14) - #388 Deepwood cross-career overcharge presentation [verify-fix; coop-required]

- Corrected the issue's original mechanism: Deepwood Staff uses `overcharge_system`, not Moonfire's `energy_system`. Vanilla binds its green HUD palette, thorn screen particles, warning sounds, decay, and non-exploding policy to `OverchargeData.we_thornsister` when the player extension is created, so a Kruber port receives generic defaults before equipment is considered.
- Added a reversible owner-side profile while `we_life_staff` occupies the ranged slot on a non-Sister career. It projects the native Sister values into the existing extension, clears stale screen particles on each ownership transition, and restores every captured field/sound when the staff leaves or WT is disabled. Existing owner-authoritative overcharge replication remains unchanged; no RPC, NetworkLookup value, or remote-husk mutation was added.
- Added a deferred post-draw override on the lazily loaded `OverchargeBarUI` so local and spectated Deepwood users receive the exact native green threshold colors. Moonfire and every Sienna/Bardin overcharge weapon remain on their existing paths.
- Added three Lua 5.1 tests and `/wt_regression_test` check `issue388_deepwood_overcharge_profile` for exact identity, native profile projection, green threshold selection, owner-only wiring, lazy HUD integration, and baseline restoration.

### Co-op verify

Both players run this build. Player A equips Deepwood Staff on a Kruber career, generates low/medium/high overcharge, then swaps to another ranged weapon and back while Player B observes and briefly spectates A. The owner and spectator bars must use the native Sister green palette; A must hear the life-staff warning progression and see thorn screen effects; the staff must decay and lock out without a generic overcharge explosion. After removal, a Sienna staff and Moonfire Bow must retain their own presentation. Repeat with B as owner. Expect one bounded profile apply/restore line per equipment transition and no RPC/desync errors.

## 0.12.239-dev (2026-07-14) - #400 cross-career Flamestorm 3P aim [verify-fix; coop-required]

- Corrected the observer-side Flamestorm Staff flame stream on non-Sienna careers. The particle still begins at the authored 3P staff-tip `fx_muzzle`, but its orientation now follows the wearer's replicated `aim_direction` instead of the receiver-native substitute pose.
- Vanilla splits the surfaces: the owner action uses the universal first-person rig for both its local particle and damage direction (`action_flamethrower.lua:64-89,226-228`), while `WeaponSystem` creates and repositions the replicated 3P particle from the weapon muzzle rotation (`weapon_system.lua:470-487,744-774`). WT changes only that replicated observer surface; damage, the owner-local first-person stream, native Sienna careers, Drakegun, and weapon transforms remain untouched.
- Both replicated creation and continuous update seams use the same correction helper. A one-time `[wt:400] applied` line confirms each observed wielder without per-frame logging. Offline policy/wiring tests and `/wt_regression_test` lock target scope, both hooks, and the replicated-aim contract.
- `[verify-fix; coop-required]`: one player equips Flamestorm Staff on Kruber, Kerillian, or Saltzpyre and aims horizontally, upward, and downward while firing; a second player confirms the 3P stream begins at the staff tip and follows the crosshair direction. Repeat once on Sienna as the unchanged native control.

## 0.12.237-dev (2026-07-13) - #341 Bolt Staff primary overcharge option [not deployed]

- Added an off-by-default Weapon Tweaks option that reduces the overcharge generated by both alternating Bolt Staff primary bolts by exactly 40%. Charged bolts, damage, projectile behavior, and firing cadence are unchanged.
- The option snapshots and scales only `PlayerUnitStatusSettings.overcharge_values.spark`, the key used exclusively by `staff_spark_spear_template_1.actions.action_one.default` and `.rapid_left` (`staff_spark_spear.lua:24,108`). Vanilla's charged-projectile utility reads that key and applies it through `add_charge` at fire time (`action_charged_projectile.lua:41-58`), so the option needs no action hook and is live-toggleable.
- Disabling the option or WT restores the exact captured baseline. Offline tests cover the 0.6 multiplier, live apply/revert, unrelated-key isolation, and unavailable-table fail-closed behavior; `/wt_regression_test` locks the two primary action keys and current live scalar.
- Solo verification: enable the option, fire ten uncharged primary bolts from zero overcharge, and compare the heat gained with the option off. The enabled result should be about 60% of vanilla; charged-bolt heat should be unchanged.

## 0.12.236-dev (2026-07-13) - #269 receiver-local holstered staff fallback [not deployed]

- Extended the existing `GearUtils.link_units` guard at its single universal boundary. When a receiver body lacks an `a_unwielded_*` source but does author `j_hips`, WT now passes a copied link using `j_hips`; other missing source/target links remain dropped.
- This fixes the Deepwood Staff disappearing while holstered in a Kruber ranged slot without mutating the shared staff template. Native Kerillian/Sienna bodies keep their authored mount because a present source remains a zero-copy no-op.
- Vanilla provenance: `GearUtils.link` dispatches the flat phase array to `GearUtils.link_units`, which immediately resolves both nodes with `Unit.node` (`gear_utils.lua:286-308`); the staff linking tables author `a_unwielded_staff` only in `third_person.unwielded` (`attachment_node_linking.lua:2938-2957`, with sibling staff rows at `:2974-2993` and `:3010-3029`).
- Regression coverage proves the Kruber-style missing node becomes `j_hips`, the original table is not mutated, and a native authored `a_unwielded_staff` link remains untouched. Solo verification: equip Deepwood Staff in a Kruber ranged slot, wield the primary weapon, and confirm the staff renders holstered at the hip in both the inventory preview and a mission.

## 0.12.235-dev (2026-07-13) - #2 split template remap data from the event-hot funnel [not deployed]

- Extracted the 1,900-line declarative `_3p_template_remaps` catalog into `_wt_anim_remap_data.lua`; `_wt_anim_remap.lua` now contains the redirect logic, state, hooks, commands, and resolvers and is below the 2,500-line hard limit.
- The sibling is a one-time builder loaded from the entry manifest immediately before `_wt_anim_remap.lua`. It receives the three pre-existing remap dependencies, returns the same mutable table object, and adds no hook, command, runtime lookup, or per-event allocation. The entry's port patchers and `/wt_regression_test` continue to share that returned table by reference.
- Updated the #290 textual invariant to follow its moved Billhook merge and added a #2 invariant locking the single builder load seam. Full verification is `qa/run_all.ps1`; in-game smoke verification remains required because this is a load-order-sensitive Lua module split.

## 0.12.234-dev (2026-07-13) - #321 retire stale Big Rebalance product surface [verify-fix]

- Big Rebalance remains intentionally unloaded and its `br_*` option catalog remains hidden. Removing the old `bt` gate would be unsafe without a registration owner, recovered source, and peer-parity design.
- Removed the retired feature from the Workshop description. Old saved `br_*` values remain reserved and ignored; no migration deletes user settings.
- Added the repository-wide blocking `qa/check_retired_big_rebalance.ps1` contract. Verify solo that no Big Rebalance group appears in Mod Tweaker.

## 0.12.233-dev (2026-07-13) - #316 Kruber Longbow zoom probe [not deployed]

- Source review separates the owner camera from the body animation: vanilla `ActionAim` starts camera zoom after the Empire Longbow's authored 0.22-second delay on every career, while WT's existing v0.12.192 `draw_bow -> to_zoom` mapping affects only third-person presentation on Mercenary, Foot Knight, and Grail Knight. Huntsman remains native.
- Because #316 contains no log or current-build reproduction, this build does not speculate with another behavior mutation. It arms a three-attempt, owner-only `[wt:316]` probe for the exact three non-Huntsman Kruber careers and Empire Longbow templates.
- Each attempt emits one start row and one bounded result row. `finished_before_observation` means aim ended before the probe observed the authored zoom time; `not_zoomed` isolates the failure to `ActionAim`/status state; `zoomed zoom_mode=zoom_in` with no visible FOV change isolates it to camera presentation. No chat, RPC, remote-player work, or per-frame output remains after the result.
- Offline coverage locks exact target scope, due-time observation, one-shot completion, and the three-attempt cap. `/wt_regression_test` adds `issue316_kruber_longbow_zoom_contract` for the vanilla action fingerprint, all three cross-career remaps, Huntsman exclusion, and probe bound.
- **Solo verify after deployment:** equip Kruber's Longbow on Mercenary, Foot Knight, and Grail Knight. On each career hold aim for at least one second, up to three total attempts per session, and confirm the first-person FOV zoom plus the third-person aim pose. Save the `[wt:316]` rows and `/wt_regression_test` result. No co-op tester is required for this owner-camera issue.

## 0.12.232-dev (2026-07-13) - #594 Saltzpyre Hammer+Shield ownership [not deployed]

- Removed Bardin's native `dr_shield_hammer` from Witch Hunter Captain, Bounty Hunter, and Zealot availability. Kruber's `es_mace_shield` remains the human-faction control for those careers.
- Removed the three dead menu/localization rows and added migration tombstones so an enabled setting from an older build cannot leave Saltzpyre in `ItemMasterList.dr_shield_hammer.can_wield` or a stale WT backend loadout.
- The exclusion is unconditional: absent, active, disabled, and hot-reloaded CWV states produce the same native ownership. CWV's separately authored variants are untouched.
- Vanilla provenance: both items use sibling clones of the common `1h_hammers_shield.lua` base; Bardin's `_template_2` adds three light-attack range modifiers at lines 1350-1352, so this is an ownership/theme decision rather than a claim of byte-identical templates.
- Offline and `/wt_regression_test` coverage lock map, menu, localization, stale migration, backend rejection, and CWV independence. In-game verification remains required.

## 0.12.231-dev (2026-07-13) - #458 transition-safe shared peer parity [not deployed]

- The shared parity beacon preserves a positive same-peer acknowledgement across a bounded 15-second PlayerManager roster absence during level transitions and delays missing-peer chat for 10 seconds. New, expired, or never-confirmed peers remain fail-closed immediately; this removes the observed false disable/re-enable chat cycle without relaxing wire safety.

## 0.12.230-dev (2026-07-13) - #290 Kruber Billhook bake preserves receiver-facing remaps [diagnostics-armed]

- **Root cause:** the complete v0.12.102 `two_handed_billhooks_template.es_` safety map was created first, then the v0.12.203 baked-picks block replaced it wholesale with five rows. Those five keys are Billhook 1P `anim_event` names, but vanilla sends `anim_event_3p or anim_event` to the 3P body (`weapon_unit_extension.lua:512`). Every action with an authored `anim_event_3p` therefore bypassed the replacement table, explaining the reported loss of essentially all Kruber Billhook swings.
- **Systemic fix:** the five preserved tester picks now merge into the complete Billhook-to-polearm map instead of replacing it. The effective Billhook 3P vocabulary is source-derived from `2h_billhooks.lua`; safe native passthroughs are source-derived from `halberds.lua`. `/wt_regression_test` now proves every effective event is either remapped or native on Kruber's polearm body and specifically locks the four receiver-facing rows the old bake deleted.
- **Automatic evidence:** the next actual Kruber `wh_2h_billhook` attack emits bounded `[wt:290]` rows without a command or picker toggle (one per source/target/outcome, maximum 48). The prior log only selected Billhook; its attack trace was `we_spear`, so it could not verify this path.
- **Verify after deployment:** on any Kruber career, equip Saltzpyre's Billhook and perform the full light chain, both charged heavies, push, and special hook. Confirm visible 3P body motion and `[wt:290] weapon=wh_2h_billhook ... origin=template:two_handed_billhooks_template` with mapped targets (or documented polearm-native passthrough), no `source_event_has_no_remap_target` for a non-native event.

## 0.12.230-dev (2026-07-13) - #593 conditional CWV Axe+Shield ownership [untested]

- WT still offers Bardin's native `dr_shield_axe` controls to all four Kruber careers when CWV is absent or disabled. When CWV is active, WT yields only that native pair to the canonical CWV variants.
- Added a dedicated `cwv_conditional_managed` policy beside the legacy overlap map. Its `can_wield` mutations are always stripped before a non-yielded enabled pair is restored, making enable, disable, removal, and hot-reload transitions idempotent without changing unrelated CWV overlap policy.
- Backend ownership checks use the same live policy and prune stale cached native loadouts on the exact CWV active-state transition. WT controls/localization remain so saved preferences become live again when CWV is disabled.
- Added host and runtime coverage for WT-only, WT+CWV, disable/removal, re-enable, UI persistence, and runtime `can_wield` parity.
- **Verify:** enable one Kruber `Bardin: Axe and Shield` WT toggle. With CWV disabled, native Axe+Shield must equip. Enable CWV: the native item must stop resolving and both CWV variants must remain. Disable CWV without restarting: the native WT option must return. Re-enable CWV and repeat; no duplicate item, stale loadout, or restart requirement.

## 0.12.229-dev (2026-07-13) - #587 baked weapon transforms on remote husks [verify-fix; coop-required]

- Vanilla remote wield is a separate renderer: `SimpleHuskInventoryExtension._wield_slot` resolves the replicated base item/career and calls `GearUtils.spawn_inventory_unit` directly, never `GearUtils.create_equipment` (`simple_husk_inventory_extension.lua:641-782`). WT now applies the same shipped scale/grip tables to those populated 3P husk units at wield time.
- Durable offsets now weak-track owner, bot, and remote-husk 3P units at spawn/wield and reconstruct `boxed canonical position + baked delta` after animation stomps. The Scythe (`bw_ghost_scythe`, Kruber +0.6 Z) and Glaive (`we_2h_axe`, Kruber +0.285 Z) therefore persist on every renderer and across re-wields/respawns.
- Transient Hold-Pose slider motion remains local-player 3P only. There is no transform RPC, channel, per-frame payload, or mutable clone identity on the wire; each WT client deterministically resolves the vanilla base key and career. Position, scale, and #569 canonical rotation continue through independent setters, and 1P is untouched.
- Added bounded `[wt:587]` registration diagnostics (maximum 24 per session) and `/wt_regression_test` coverage for payload bounds, Scythe + second transformed weapon, native/unmodified controls, ownership scope, and component composition. Workshop not uploaded.
- **Co-op verify:** both players run v0.12.229-dev. Player A equips Kruber Scythe, Kruber Glaive, then an unmodified Kruber 1H Sword while Player B watches in keep and mission; swap away/back and respawn once. Owner 3P, remote view, and preview must agree for both transformed weapons; control and 1P remain vanilla. Repeat with Player B as wielder. Confirm bounded `[wt:587] tracked role=remote_husk... transport=none` lines and no recurring network/transform log spam.

## 0.12.228-dev (2026-07-13) - #585 Moonfire HUD clears after loadout replacement [untested]

- Vanilla `EnergyBarUI` checks only whether the always-present energy extension is below full; it never checks the ranged item. On non-Kerillian careers the native recharge rate is zero, so drained Moonfire energy remained below full forever after replacing the bow and the HUD kept drawing.
- The owner-side passive-charge planner now selects exactly one action from the equipped ranged slot: recharge Moonfire at 1.5/s, or reset a stranded nonnative energy value to max after Moonfire is removed. Full values schedule no repeated work.
- The reset uses the existing clamped `energy_system:add_energy` consumption-side API. Native Kerillian's nonzero rate returns before inventory inspection, and #584's melee-active Moonfire recharge remains intact.
- Added one bounded `[wt:585]` info record per successful stale-HUD reset, runtime regression `issue585_moonfire_energy_hud_loadout_lifecycle`, and two offline lifecycle tests. No Workshop deployment.

## 0.12.227-dev (2026-07-13) - #584 Moonfire recharge while stowed [untested]

- Changed the cross-character Moonfire eligibility check from the currently wielded item to the equipped `slot_ranged` item, matching vanilla Kerillian behavior while melee is active.
- Kept the existing local-owner-only `energy_system:add_energy` path and native 1.5 energy/s rate. Careers with a nonzero native `_recharge_rate` remain untouched.
- Wielded and stowed states share one recharge planner/call site, so switching slots cannot double-apply. Replacing Moonfire with an ammo bow or clearing the ranged slot removes eligibility immediately.
- Added `/wt_regression_test` check `issue584_moonfire_stowed_native_regen_contract`. No Workshop deployment.

## 0.12.226-dev (2026-07-13) - #582 native-vs-CWV Dual Axes ownership [untested]

- Removed Bardin's native `dr_dual_wield_axes` from all four Kruber and all three standard Saltzpyre unlock maps, settings controls, localization rows, and dev-picker availability. Bardin remains native and Kerillian is outside this issue's scope.
- Added explicit removed-pair tombstones in `_wt_availability.lua` so `can_wield` mutations left by an older/hot-reloaded WT build are stripped even though the pair is no longer in the active unlock map.
- WT's backend now eagerly prunes invalid cached cross-career loadouts when its item interface becomes ready. Its existing read-side validation continues to reject a removed native Dual Axes id and falls through to the vanilla career loadout.
- Preserved the `dual_wield_axes_template_1` ES/WH animation mappings because CWV's dedicated `cwv_es_dual_axes` and `cwv_wh_dual_axes` variants still consume that template.
- Added `/wt_regression_test` check `issue582_native_dual_axes_cwv_ownership_boundary`. No Workshop deployment.

## 0.12.225-dev (2026-07-13) - #580: Saltzpyre Moonfire crossbow presentation [untested]

- Saltzpyre's Witch Hunter Captain, Bounty Hunter, and Zealot now render the Moonfire Bow (`we_deus_01`) as Saltzpyre's native crossbow in third person. The existing longbow presentation pipeline is reused for local-body, remote-husk, inventory/hero-preview, crossbow attachment-linking, and bolt-prop paths.
- Added a `we_deus_01_template_1.wh_` runtime event map: `attack_shoot_fast -> attack_shoot`, `attack_shoot_fast_last -> attack_shoot_last`, and `draw_bow -> to_zoom`. The existing shared wield patch supplies `to_crossbow`; Warrior Priest remains excluded.
- First-person Moonfire is deliberately untouched: bow mesh, longbow state machine, energy actions, projectiles, aim/fire events, and generic reload transition retain vanilla values.
- Added bounded `[wt:580]` template diagnostics and regression check `issue580_moonfire_saltzpyre_crossbow_3p_contract`. Workshop not uploaded.

## 0.12.224-dev (2026-07-13) - #536: receiver-native volley reload + local 3P replay [untested]

- Vanilla `GenericAmmoUserExtension.start_reload_animation` plays reload on the first-person unit and forwards the RPC away from the originating client, but never plays it on that client's third-person body. The originating player now receives one local-only 3P replay after the unchanged vanilla 1P/network path; no extra RPC is sent.
- Elf Volley Crossbow on standard Saltzpyre careers now re-arms the receiver-native `to_repeating_crossbow` stance before the unchanged generic `reload`/`reload_last` event. This selects Saltzpyre's volley-crossbow sequence instead of the ordinary crossbow graph while preserving native weapons and Kerillian's native elf receiver.
- Added bounded raw-log-only `[wt:536:reload]` diagnostics for missing/rejected events and dispatched-but-unverified transitions. Event existence and successful dispatch are explicitly not treated as visible-playback proof.
- Added regression contracts for receiver-native volley routing and vanilla reload-event precedence.
- **Verify:** in local 3P, fire and reload Elf Volley Crossbow on WHC/BH/Zealot; the reload must be visible and use the volley sequence. Repeat with native Saltzpyre Repeater and native Kerillian Volley Crossbow, then observe the port from a second peer. Run `/wt_regression_test` and retain `[wt:536:reload]` evidence. No Workshop deployment in this change.

### Source evidence

- `generic_ammo_user_extension.lua:287-332` omits a local owner-body animation call; `animation_system.lua:358-375` forwards a client-originated animation to every client except its origin.
- Native Saltzpyre and elf repeater templates both emit generic `reload`, but enter different receiver stances: `to_repeating_crossbow` versus `to_repeating_crossbow_elf` (`repeating_crossbows.lua:245-250`, `repeating_crossbows_elf.lua:257-262`).

## 0.12.223-dev (2026-07-13) - #576: reopen false-confirmed 3P ports; bounded playback diagnostics [untested]

- Reopened Ensorcelled Reaper and Elf Spear on standard Saltzpyre careers after live tests disproved their static `[working]` status. Both are back in the 3P picker; confirmation requires complete source-event coverage plus explicit human visual evidence.
- Scythe H1/H2/H3 charges/releases no longer collapse onto one WP-Greathammer event. Elf Spear now uses Billhook `anim_event_3p` values instead of divergent 1P names; H1 charge and committed heavy remain separate obligations.
- Added bounded, deduplicated, raw-log-only `[wt:576]` records with weapon/template, career, phase, source, target, remap origin, and outcome. Outcomes distinguish unmapped source, missing target, call error, and accepted-but-unverified/no observable transition. No chat output.
- Standard Saltzpyre careers now offer Kruber's Empire Greathammer (`es_2h_hammer`, `two_handed_hammers_template_1`) and exclude Bardin's analogous `dr_2h_hammer`.
- **Verify:** enable the 3P Anim Picker; test all Reaper rows and Elf Spear H1 hold/release. Expect separate `h1_charge_start`, `h1_charge_loop`, `h1_charge_release`, and `h1_committed_attack` records. Successful records remain unverified until visible playback is recorded. No Workshop deployment in this change.

## 0.12.222-dev (2026-07-13) - #569 follow-up: Hold-Pose preserves corrected/baked transforms [untested]

- Latest logs prove `0.12.221-dev` applies the Saltzpyre WP-remap half-turn, after which live Hold-Pose position tuning writes an absolute identity-rotation pose every frame and clobbers it. Right-hand Z changed repeatedly while pitch/yaw/roll stayed zero; the regression is an ownership collision, not a bad #569 axis.
- Reworked Hold-Pose sliders as independent deltas over one captured canonical/baked 3P baseline. Position uses only `Unit.set_local_position`; rotation uses only `Unit.set_local_rotation` with `base * delta`; scale is never written. Editing one component therefore preserves the other two, and every frame is rebuilt from the baseline so values cannot compound.
- #569-tracked units expose their authoritative canonical-or-corrected rotation to the tuner, eliminating hook-order ambiguity. The tuner remains local-player 3P-only; #569's preview/bot/remote-husk ownership and all 1P units remain untouched.
- Returning a component to zero restores its baseline once, then becomes a true no-op. `/wt_dev_hp_reset` restores dirty cached components immediately before clearing the cache.
- Expanded `issue569_wp_hammer_remap_orientation_scope` with position-only, rotation-only, zero/no-op, scale-preservation, scope, and no-compounding contracts.

## 0.12.221-dev (2026-07-13) - #569: Saltzpyre WP-remap 3P orientation [untested]

- **Symptom:** non-native weapons on `wh_captain`, `wh_bountyhunter`, and `wh_zealot` faced backwards when their live 3P wield target was `to_2h_hammer_priest`. The animation family remains the intended one; the linked weapon-root orientation was wrong.
- **Source boundary:** `AttachmentNodeLinking.two_handed_melee_weapon.third_person.wielded` links body `j_rightweaponattach` directly to weapon node `0` with no rotation (`attachment_node_linking.lua:2836-2864`), and `GearUtils.spawn_inventory_unit` performs that link before returning the 3P unit (`gear_utils.lua:150-185`). The candidate therefore corrects weapon node 0 after spawn and never touches 1P or the shared template.
- **Axis:** local Z is WT's established haft/grip axis (`_weapon_grip_offsets`: +Z moves the grip down the haft). An exact 180-degree local-Z axis-angle turn flips transverse facing without reversing the longitudinal head-to-grip direction. The correction is recomputed from a boxed canonical rotation, never from the previous frame, so it cannot double-rotate.
- **Scope:** the predicate requires a standard Saltzpyre career plus a live `wield_anim_career_3p[career] == "to_2h_hammer_priest"`, excludes `wh_priest`, and explicitly exempts `wh_2h_hammer`. Only tracked `*_unit_3p` roots are written. Wielded local-player, bot, remote-husk, and preview units are covered; unwielded units restore their captured canonical rotation.
- **Diagnostics/regression:** raw `[wt:569] tracked` and state-change `applied=true/false` lines identify the exact unit path. `/wt_regression_test` adds `issue569_wp_hammer_remap_orientation_scope` for career/remap scope, native exemption, exact axis, and exact angle.
- **Verify after integration:** on a standard Saltzpyre career, inspect at least two mapped families (for example Bardin Greataxe and Cog Hammer) in local 3P and from a second player's view; both must face forward through idle/attacks/swap. Then equip the native WP greathammer on Warrior Priest as the unchanged control.

## 0.12.220-dev (2026-07-13) - #286: Greataxe Saltzpyre pose post-fix lock

Post-fix hardening for the already user-confirmed v0.12.205-dev Greataxe stance correction. No gameplay value changed in this build.

- **Regression:** new `issue286_greataxe_saltzpyre_wield_pose` check locks `wt_wield_patches.bulk.two_handed_axes_template_1` for `wh_captain`, `wh_bountyhunter`, and `wh_zealot` to `to_2h_hammer_priest`, then checks the applied live `Weapons` table when available. It fails if either layer returns to the old `to_2h_sword` stance.
- **Docs:** `DEVELOPMENT.md` now records this weapon-specific wield redirect and its regression owner beside the other known remaps.
- **Verify:** run `/wt_regression_test`; expect `issue286_greataxe_saltzpyre_wield_pose: PASS`. Human visual verification is already recorded on issue #286 against v0.12.205-dev.

## 0.12.219-dev (2026-07-13) - #411: dead Anim Picker sources fail loud

The stale Bastard Sword `swap_charge_stance` picker row is no longer present: `es_bastard_sword` was tuned and baked in v0.12.213-dev (#519), which removed all of its picker catalog entries. This build locks that outcome and generalizes the picker's own `n=0` diagnostic into a full-catalog regression check so the same class cannot silently return on another weapon.

- **Hardening:** `wt_dev_anim_picker.source_event_coverage()` walks every registered picker weapon/source event and requires a matching live `Weapons.<template>.actions.*.*.anim_event`. Missing DLC templates are reported separately rather than misclassified as stale source rows.
- **Evidence:** install prints `[wt:411] picker source coverage: weapons=N events=N dead=0 ...`; every dead row is printed with weapon, event, and template. `/wt_regression_test` now includes `issue411_dev_picker_source_events_resolve_live`.
- **Verify (solo, keep):** run `/verify_wt_anim_picker_sources`; expect `PASS` and zero `[wt:411] dead picker source` lines. Enable the 3P Anim Picker and confirm no Bastard Sword / `swap_charge_stance` row is offered (the baked Saltzpyre mapping remains in `_wt_anim_remap.lua`).

## 0.12.218-dev (2026-07-13) - #408: Weapon Availability sorts by visible name

Weapon Availability rows now sort alphabetically by the tag-stripped player-facing English label instead of source-character rank and internal weapon key. This puts entries where their visible names say they belong (including Saltzpyre's Flail on Kruber) and keeps computed `[working]` / `[untested]` / `[needs animations]` tags out of the sort key.

- **Root cause:** the v0.12.199-dev #179 central pass deliberately sorted by weapon-key prefix (`es`, `dr`, `wh`, `we`, `bw`) and then raw key. Its `all_unlock` guard also skipped a whole career leaf if any unrelated child appeared there.
- **Fix:** `weapon_tweaker_data.lua` resolves each row from `mod._wt_loc_raw[setting_id].en` (the #197-safe pre-registration localization path), strips every leading bracket tag, and sorts only unlock rows back into their original unlock slots. The setting id is a deterministic fallback/tie-break; widget ids/defaults are unchanged.
- **Evidence:** boot prints `[wt:408] applied: sorted N Weapon Availability rows by tag-stripped display name`. Run `/verify_wt_availability_sort` in the keep; it reports every checked career leaf and any adjacent out-of-order pair. `/wt_regression_test` includes the same `issue408_availability_rows_sorted_by_name` invariant.
- **Verify (solo, keep):** open Mod Options -> Tweaker: Weapons -> Weapon Availability -> Kruber -> any melee career. Rows should increase alphabetically by their visible source/name text after ignoring the leading status tag; specifically, `Saltzpyre: Flail` must appear in the S section rather than at the top.

## 0.12.217-dev (2026-07-13) - #218: remove dead CIM widget-strip scaffolding

The Chaos Wastes trait groups `cw_melee_traits` and `cw_ranged_traits` were deleted from the settings tree in commit `a7012f3`, but their `crafting_in_modded` detection and recursive strip pass remained at data-load time. Current active wt source contains no such widget or localization key, and the decompiled game source contains none of these mod-only setting IDs, so the walk could never remove anything.

- Removed only the stale CIM presence scan, gated-ID table, recursive strip helper, call site, and comments that described that deleted path from `weapon_tweaker_data.lua`. Dynamic dev widget trees still append in the same order.
- Marked `enable_weapon_backend_hooks`, `enable_weapon_ui_hooks`, and `enable_weapon_animation_redirects` as intentional hidden default-true feature-flag labels in `weapon_tweaker_localization.lua`; their runtime reads remain unchanged.
- **Static regression:** four `#218` entries in `qa/rt_textual_invariants.psd1` require the removed CIM symbols/groups to remain absent from active wt data and the three runtime-backed hidden labels to remain present.
- **Verify (static/no gameplay change):** `qa/check_rt_textual_invariants.ps1`, strict `tools/mod-lint/lint-mod.ps1 -Mod weapon_tweaker`, and relevant repository QA pass. No in-game behavior changes; live confirmation is not applicable to this no-op removal.

## 0.12.216-dev (2026-07-13) - #536: extend the empty-wield network-crash patch to Saltzpyre (wh) careers

Closes the wire-safety-audit finding in issue #536: the not-loaded/no-ammo wield patch (`_NOT_LOADED_NO_AMMO_CAREER_PATCHES`, `weapon_tweaker.lua`, added v0.12.139) covered only Kruber careers, so a Saltzpyre career wielding Kerillian's Repeater Crossbow (`we_crossbow_repeater`, `repeating_crossbow_elf_template`) on an empty/unloaded clip still hit the same latent RPC-packer fatal.

- **Crash class (network game only, bypasses pcall).** The elf template's base `wield_anim_not_loaded = "to_repeating_crossbow_elf"` / `wield_anim_no_ammo = "to_repeating_crossbow_elf_noammo"` [src: `repeating_crossbows_elf.lua:258-259`] are NOT in `NetworkLookup.anims` (no `_elf` entries exist [src: `anims_lookup_table.lua`]). On an empty-clip wield the engine resolves the career override via `get_wield_anim(base, base_career, career_name)` [src: `simple_inventory_extension.lua:1922-1924, 2050`] and hands it to `ammo_extension:start_reload(..., override_wield_anim)` [`:2063`], which stores it as `_override_reload_anim` [src: `generic_ammo_user_extension.lua:490,498`]; the reload completes at `:311` -> `event_id = NetworkLookup.anims[reload_event]` -> nil [`:323`] -> `send_rpc_clients("rpc_anim_event", nil, go_id)` [`:327/329`] = C-level packer fatal on the wt shooter's own machine.
- **Why wh was missed.** The v0.12.139 fix table shipped Kruber-only (`es_*`). The wh careers were later given the LOADED 3P wield (`wt_wield_patches.lua:199`, `#441`) but never added to the NOT-LOADED/NO-AMMO table, so the raw unregistered `_elf` names survived on the empty-wield send path for Saltzpyre.
- **Fix (3P-ONLY, data-only).** Extended the SAME mechanism to a per-receiver-group form: `repeating_crossbow_elf_template` now maps to a list of groups - Kruber -> `to_repeating_handgun` / `_noammo` (unchanged), wh (`wh_captain` / `wh_bountyhunter` / `wh_zealot`) -> `to_repeating_crossbow` / `to_repeating_crossbow_noammo`. Both wh fallbacks are Saltzpyre's OWN Volley Crossbow wields [src: `repeating_crossbows.lua:246-247`], NetworkLookup-REGISTERED [src: `anims_lookup_table.lua:645-646`] and authored by the witch_hunter 3P body. These write into `wield_anim_not_loaded_career` / `wield_anim_no_ammo_career`, both vanilla-read fields (`get_wield_anim`) - no new hook. Career set confirmed from the unlock map (`wt_unlock_data.lua:142-144`).
- **wh_priest (DLC bless) is out of scope, no gate needed.** It never receives this weapon (`wt_unlock_data.lua:145` omits it; `/wt_regression_test` `wh_priest_no_bows` asserts wh_priest gets no bows/crossbows). The patch is a pure data write that stays inert for any career that can't wield the item, so no DLC gate is required (matching the existing Kruber `es_questingknight` Grail-Knight entry, ungated for the same reason).
- **Wire verdict (PROJECT_STANDARDS §9.3).** This IS the wire-safety fix: it is a sender-side swap of an UNregistered anim name for a vanilla-REGISTERED one BEFORE the `rpc_anim_event` send, applied UNCONDITIONALLY at load (not toggle-gated), matching the #278/#371 sender-swap doctrine. It adds NO `NetworkLookup` registration (the fallback indices already exist on every peer, vanilla) and repoints no damage profile, so the `#431` peer-parity floor (`_wt431_damage_profile_parity.lua`) is not applicable. The RPC now carries a lookup index every peer (wt or not) resolves.
- **Regression:** `repeater_empty_wield_network_patch_all_careers` in `/wt_regression_test` - asserts the live `Weapons.repeating_crossbow_elf_template.wield_anim_not_loaded_career` / `wield_anim_no_ammo_career` route all four Kruber careers to `to_repeating_handgun`/`_noammo` AND all three wh careers to `to_repeating_crossbow`/`_noammo`, and that wh_priest is NOT patched.
- **Diagnostics:** existing `[wt:dbg] [wt:tpl_patch] event=applied template=repeating_crossbow_elf_template not_loaded/no_ammo careers=7` at load (was 4), printf/debug-log-only per rule 9.
- **Verify (cross-peer, verify-fix + coop-required, needs a wt host + a NON-wt client = 2 people).** Load line `[wt:LOAD] v0.12.216-dev`; `/wt_regression_test` all-pass. Repro: on any non-WP Saltzpyre career (WHC / BH / Zealot), enable `we_crossbow_repeater` availability, equip Kerillian's Repeater Crossbow, fire it to empty (or swap to it while its clip is empty) so the empty-clip wield/reload fires while a NON-wt client is in the mission. Expected: no crash on either machine (baseline: pre-fix this crashed the wt wielder's own client). Files: `weapon_tweaker.lua` (MOD_VERSION; patch table -> per-group form + apply loop + regression check).

## 0.12.215-dev (2026-07-13) - #535: register the moonfire AoE template into NetworkLookup.explosion_templates (latent CTD class, wire-inert)

Closes the wire-safety-audit finding in issue #535: the pre-nerf Moonfire Bow AoE revert template (`wt_moonfire_aoe_revert`) was registered into `ExplosionTemplates` only, never into `NetworkLookup.explosion_templates`. That table is frozen at engine boot with a strict `__index` that hard-errors on any missing key [src: `scripts/network_lookup/network_lookup.lua` build `:1211`, strict `__index` `:2360-2367`], so IF an AoE path ever encoded the name (`NetworkLookup.explosion_templates[name]`) the encode would insta-crash the wt user's own machine.

- **Wire-path analysis (the encode is unreachable today).** The moonfire hook calls `DamageUtils.create_explosion` DIRECTLY (`_wt_moonfire_on_hit`), never `AreaDamageSystem.create_explosion`. `DamageUtils.create_explosion` never encodes via `NetworkLookup.explosion_templates`; its only AoE-network touch is `area_damage_system:add_aoe_damage_target` [src: `damage_utils.lua:1470`], which stores the name as a STRING in a host-only local ring buffer and resolves it through `ExplosionUtils.get_template -> ExplosionTemplates[name]` [src: `area_damage_system.lua:280,331,347`], never `NetworkLookup`. The ONLY `NetworkLookup.explosion_templates[name]` encode in the explosion path is `AreaDamageSystem.create_explosion` [src: `area_damage_system.lua:162`], which the moonfire path never reaches. So the name never rides the wire: no strict-`__index` fatal on encode (wt shooter) and none on decode (a non-wt peer). Full trace added to `ENGINE_SURFACE.md`.
- **Fix (belt-and-suspenders, PROJECT_STANDARDS §9.3).** Register `wt_moonfire_aoe_revert` into `NetworkLookup.explosion_templates` UNCONDITIONALLY at load - forward + reverse append, `rawget`-guarded (registers once), mirroring the existing `NetworkLookup.damage_profiles` append idiom (`weapon_tweaker.lua:~1891`). This satisfies index determinism across wt peers and eliminates the footgun should a future change ever route moonfire through `AreaDamageSystem.create_explosion`.
- **Wire-safe fallback recorded.** `mod._wt535_explosion_template_fallback[wt_moonfire_aoe_revert] = "machinegun_poison_arrow"` - the closest vanilla explosion template (identical shape: `damage_profile "poison_aoe"`, sound `arrow_hit_poison_cloud`, `no_prop_damage`, `use_attacker_power_level` [src: `scripts/settings/explosion_templates.lua:6-15`]). This is the substitute a sender-side floor WOULD coerce to; no active floor hook is installed because moonfire has no `NetworkLookup` send path (analysis above) and hooking the hot vanilla `AreaDamageSystem.create_explosion` would tax every vanilla explosion for a path moonfire never uses. Same map shape as the #431 damage-profile fallback.
- **Regression:** `wt_535_moonfire_explosion_registered` in `/wt_regression_test` - asserts the template is present in `ExplosionTemplates` with its `.name`, that `NetworkLookup.explosion_templates` resolves it both directions (name->idx, idx->name), and that the recorded vanilla fallback is a real vanilla name that resolves in the lookup.
- **Diagnostics:** `[wt:535]` printf on registration (index + wire-inert note), log-only per rule 9.
- **Verify (cross-peer, verify-fix + coop-required, needs a wt host + a NON-wt client = 2 people).** Load line `[wt:LOAD] v0.12.215-dev` + `[wt:535] registered wt_moonfire_aoe_revert...`; `/wt_regression_test` all-pass. Repro the AoE: enable `moonfire_aoe_revert` (Weapon Tweaks), the wt host equips a Moonfire Bow (`we_deus_01*` on any Kerillian career) and fires charged shots into enemy packs and props while the non-wt client is in the lobby. Expected: pre-nerf poison-puff AoE detonation on impact, damage host-side, FX on both screens, NO crash on either machine (baseline confirmation the encode path stays unreached). Files: `weapon_tweaker.lua` (MOD_VERSION; NetworkLookup registration + fallback map + regression check), `ENGINE_SURFACE.md` (wire-path trace).

## 0.12.214-dev (2026-07-13) - #348: opt-in revert of the 6.11.0 Kruber 1h sword push-attack combo

New opt-in toggle in **Weapon Tweaks** (`weapon_overrides` group): **"Empire Sword: revert 6.11.0 push-attack combo"** (`wt_revert_1h_sword_push_combo`, default OFF, `[untested] [Issue 348]`). Reverts the Patch 6.11.0 rework of Kruber's Empire one-handed sword (`Weapons.one_handed_swords_template_1`) push-attack chain.

- **What 6.11.0 changed (authoritative, not reconstructed):** `git diff 5ff26df1 abe82ab4 -- scripts/settings/equipment/weapon_templates/1h_swords.lua` shows the push-attack `light_attack_bopp.allowed_chain_actions` combo-continuation entry was repointed from `sub_action = "default"` (-> first light `light_attack_left`, a horizontal sweep) to `sub_action = "default_left"` (-> third light `light_attack_last`, the single-target overhead), with `start_time` 0.55->0.5, and a second `action_one_hold -> default` entry replaced by an `action_two` block entry. The toggle restores the exact v6.10.0 `allowed_chain_actions` table verbatim.
- **Scope correction:** the issue names Kruber AND Sienna, but only Kruber's Empire sword was reworked in 6.11.0. Sienna's flaming sword (`flaming_sword_template_1`, `1h_swords_wizard.lua`) has an EMPTY diff for 6.11.0 (last touched v6.4.0) and her in-game 1h sword item maps to that template - nothing to revert on her side. Toggle is Kruber-only.
- **Only the combo is reverted.** 6.11.0's other, unrelated changes to this sword (dodge_count 3->6, the third light's `damage_profile`, movement multipliers) are deliberately left as current - the issue is only about the combo routing.
- **Wire-safety:** wire-safe by construction. Only re-routes `sub_action` between vanilla action names (`default`, `default_left`, `light_attack_*`) present in the base template on every peer; adds no `NetworkLookup` key and repoints no damage profile (PROJECT_STANDARDS §9.3). Same wire class as the ungated Big Rebalance chain edits (`weapon_tweaker_big_rebalance.lua`), so no `_lib_peer_parity` gate is needed - a peer without the mod cannot diverge or crash.
- **Apply model:** applied once at init when the toggle is on (mirrors `authentic_brace_of_pistols`); mutates the shared template global in place (intended - the chain is a property of the weapon). Toggling requires a restart, stated in the option description.
- **Regression:** `wt_kruber_1h_sword_push_combo_revert` in `/wt_regression_test` - asserts `one_handed_swords_template_1.action_one.default` and `light_attack_bopp` chain exist, and (only when the toggle is ON) that `light_attack_bopp.allowed_chain_actions[1].sub_action == "default"`.
- **Verify (solo, keep or mission):** enable the toggle, restart, load line `[wt:LOAD] v0.12.214-dev` + log line `[wt:348] reverted Kruber Empire 1h sword push-attack combo...`; `/wt_regression_test` all-pass. On a Kruber career equip the Empire 1h sword, block -> push -> hold attack into the push-attack, then continue the light: the follow-up should be a horizontal sweep (first light), NOT the vertical overhead. Toggle OFF + restart = vanilla 6.11.0 overhead-terminated combo returns. Files: `weapon_tweaker.lua` (MOD_VERSION; `_patch_kruber_1h_sword_push_combo_revert` + init gate; regression check), `weapon_tweaker_data.lua` (checkbox), `weapon_tweaker_localization.lua` (label + description).

## 0.12.213-dev (2026-07-13) - #519: Saltzpyre batch-2 3P anim picks BAKED (10 of 11 ports; 129 picks)

The tester finished tuning the Saltzpyre batch-2 dev-picker set (issue #519, attached `user_settings.txt`). Both picker persistence namespaces were parsed per `reference_wt_anim_picker_two_key_namespaces` (weapon-only preferred, template-qualified fallback): all batch-2 picks live in the weapon-only namespace; the template-qualified namespace held nothing new (its only non-unset Saltzpyre residuals - `bw_1h_crowbill` up_left->left, `we_1h_axe` up->up_left, `es_halberd` wield to_2h_billhook - were verified ALREADY baked from the v0.12.203 merge). Picks baked VERBATIM, career-scoped `wh_`, into `_3p_template_remaps` (`_wt_anim_remap.lua` do-block); every target event verified authored in the target template's decompiled source (`2h_hammers_priest.lua` / `dual_wield_axe_falchion.lua` / `2h_swords.lua`, zero `anim_event_3p` overrides in all three, #196-safe). Wield-render side needed nothing: all batch-2 `wh_*` wield redirects were already in `_WIELD_ANIM_CAREER_3P_PATCHES_BULK` (`wt_wield_patches.lua`). [untested]

- **Baked (10 ports, 129 picks):** SET A -> WP Greathammer: `es_2h_hammer` (11, `two_handed_hammers_template_1.wh_`), `dr_2h_cog_hammer` (16, `two_handed_cog_hammers_template_1.wh_`), `dr_2h_pick` (12, `two_handed_picks_template_1.wh_`), `bw_1h_mace` (13, `one_handed_hammer_wizard_template_1.wh_`), `bw_ghost_scythe` (15, `staff_scythe.wh_`). SET G -> Saltzpyre 2H Sword: `es_bastard_sword` (14, `bastard_sword_template.wh_`). SET C -> Dual Axe & Falchion: `es_mace_shield` (11, `one_handed_hammer_shield_template_1.wh_`), `es_sword_shield` (12, `one_handed_sword_shield_template_1.wh_`), `es_sword_shield_breton` (12, `one_handed_sword_shield_template_2.wh_`), `dr_shield_axe` (13, `one_hand_axe_shield_template_1.wh_`). Every touched template already carried its native owner prefix = false; shield-offhand models remain a later pass.
- **NOT baked:** `dr_dual_wield_hammers` (WP Dual Hammers target) - ZERO non-unset picks in either namespace; stays in `_NEEDS_ANIMS.saltzpyre` + the dev picker for tuning.
- **Lockstep:** the 10 keys moved `_NEEDS_ANIMS.saltzpyre` -> `_CONFIRMED.saltzpyre` (`wt_port_status.lua`, Availability tag flips to `[working]`); their `_SALTZ_WEAPON_SET`/`_SALTZ_WEAPON_TEMPLATE`/`_SALTZ_WEAPON_ATTACKS` picker entries deleted (`wt_dev_anim_picker.lua`). `ANIMATION_COVERAGE.md` Saltzpyre rows flipped to wired-unverified.
- **Regression:** `saltz_batch2_wh_remaps_baked` in `/wt_regression_test` - asserts all 10 `wh_` tables are present and non-empty in `_3p_template_remaps`.
- **Verify (solo, keep or mission):** load line `[wt:LOAD] v0.12.213-dev`; `/wt_regression_test` all-pass. On any non-WP Saltzpyre career (WHC/BH/Zealot), equip each of the 10 weapons (enable its Availability toggle if off), watch the 3P body via gt third-person (`/tp`): light chain, heavy chain (4+ chained heavies), push, block. Expected stances: WP Greathammer for the five SET A weapons, Saltzpyre 2H Sword for Bret. Longsword, Dual Axe & Falchion for the four shield combos. Baseline: the same weapons on their native owners play untouched; dr_dual_wield_hammers still shows `[Needs Animations]` and stays in the picker.

## 0.12.212-dev (2026-07-13) - FIX #441: Kerillian's Volley Crossbow on Saltzpyre now shows the correct idle pose in the keep inventory preview (+ mirrored fix for Saltzpyre's Volley Crossbow on Kerillian)

**Root cause:** the keep inventory previewer resolves the 3P wield/idle pose from `item_template.wield_anim_career_3p[career]`, falling back to the template's base `wield_anim`, and fires it directly on the preview body (`world_hero_previewer.lua:1060-1065`; same pick at `:1003`). `wt_wield_patches.bulk.repeating_crossbow_elf_template` carried only the four Kruber `es_*` entries, so on Saltzpyre the previewer fell back to the elf template's base `wield_anim = "to_repeating_crossbow_elf"` (`repeating_crossbows_elf.lua:257`), an event the wh 3P body does not resolve to a Volley Crossbow stance - wrong idle pose in the preview. **In-mission 3P was already correct** because the `Unit.animation_event` funnel's `_career_anim_redirect.to_repeating_crossbow_elf` redirects non-`we_` careers to `to_repeating_crossbow` - but the preview `character_unit` has no career extension, so that path is a no-op there, and the v0.12.146 preview pose resolver (`MenuWorldPreviewer._spawn_item_unit` post-hook) is has_anim-gated and did not cover this event. Same mechanism the polearm-class wield patches fixed in v0.12.60/v0.12.139 (see the "Cross-character wield-stance template patches" block).

- **Fix (data-only, general path):** baked the receiver-native wield events into the existing shared `wt_wield_patches.lua` bulk table - the exact value the in-mission redirect already produces. `repeating_crossbow_elf_template` (`we_crossbow_repeater`) gains `wh_captain/wh_bountyhunter/wh_zealot = "to_repeating_crossbow"` (Saltzpyre's own Volley Crossbow wield, `repeating_crossbows.lua:245`; NetworkLookup-registered, `anims_lookup_table.lua:645`). Kruber `es_*` rows were already baked (`to_repeating_handgun`); Bardin/Sienna are not exposed to this weapon in the unlock map. No new hooks; the vanilla previewer, local wield (`simple_inventory_extension.lua:2011-2013`), and husk wield (`simple_husk_inventory_extension.lua:710/724`) all read the field natively, and all three consume it via direct non-networked `Unit.animation_event` (wire-safe).
- **Mirrored fix (same gap, other direction):** `repeating_crossbow_template_1` (`wh_crossbow_repeater` on Kerillian careers) had the identical preview gap - base `wield_anim = "to_repeating_crossbow"` is not elf-native. Gains `we_waywatcher/we_maidenguard/we_shade/we_thornsister = "to_repeating_crossbow_elf"` (Kerillian's native Volley Crossbow wield), the same value every other `we_`-receiver firearm row in the bulk table uses. [untested]
- **Regression:** `volley_crossbow_preview_wield_baked` in `/wt_regression_test` - guards both directions of the pair in `wt_wield_patches.bulk` plus a live `Weapons.repeating_crossbow_elf_template.wield_anim_career_3p` layer that catches an apply-order regression.
- **Verify (solo, keep):** load line `[wt:LOAD] v0.12.212-dev`; `/wt_regression_test` all-pass. Equip Kerillian's Volley Crossbow on Saltzpyre (WHC/BH/Zealot; toggle `unlock_wh_*_we_crossbow_repeater` if off) and open the inventory with the ranged slot wielded - the preview should hold Saltzpyre's native Volley Crossbow idle (compare against native `wh_crossbow_repeater`). Baseline: same weapon on Kerillian previews unchanged. Mirror: Saltzpyre's Volley Crossbow on any Kerillian career should preview in her native Volley Crossbow idle. Also spot-check in-mission 3P wield on Saltzpyre (`/tp`) - unchanged final event, so no visible change expected there.

## 0.12.211-dev (2026-07-13) - CRASH FIX #431: custom damage profiles now peer-parity gated + unconditional wire floor (non-wt peers no longer CTD)

**The crash (#431, BUG_CLASSES class 31, same class as issue 423):** wt appends its cloned damage profiles (`wt_authentic_pistol`, `wt_priest_punch_buffed`, the `wt_brettsns_*` set) to `NetworkLookup.damage_profiles`. Every attack-hit send funnels through `WeaponSystem.send_rpc_attack_hit` (`weapon_system.lua:148`); on a client it wires `damage_profile_id` to the host via `rpc_attack_hit` (`:182`), and the host decodes it at `weapon_system.lua:243`. A host WITHOUT wt never appended our keys, so the decode hits the strict `__index` (`network_lookup.lua:2360-2367`) and hard-errors. Fix per the issue's prescription: the issue 371 peer-parity framework, NOT silent substitution as a feature (substituting base profiles would change advertised balance).

- **Peer-parity beacon (new `_lib_peer_parity.lua` copy + `_wt431_damage_profile_parity.lua`).** The shared issue 371 lib (crt/ct_dev/cwv/et precedent; carries the issue 506 `_applied`-before-callbacks fix) proves "every human peer runs wt" over VMF's own mod-to-mod channel (`wt_peer_parity_present`, wire-safe by construction). One gated feature (`wt_custom_damage_profiles`) re-runs the three apply functions on every parity flip. Fail-safe posture: inert until positively confirmed; solo / bots-only lobbies confirm immediately (nothing foreign to crash).
- **The three custom-profile toggles are now parity-gated at the USE (repoint) level; registration stays unconditional** (PROJECT_STANDARDS section 9.3 index determinism across same-version wt peers - registration crashes nobody, only a wired index does). While an unconfirmed human peer is in the lobby: `wt_priest_punch_buff` and `wt_brett_sword_shield_buff` revert to vanilla whole (live, existing apply fns re-gated); `authentic_brace_of_pistols` reverts ONLY its damage-profile repoint via the new snapshot/`mod._wt431_brace_repoint` split (ammo/spread/speed stay - they never ride a lookup index). All three come back automatically once every peer has wt. Chat notice on each flip (shared-lib standard).
- **Unconditional sender-side wire floor (backstop):** new hook on `WeaponSystem.send_rpc_attack_hit` (wt's only WeaponSystem hook; pre-flight grepped) coerces any wt-custom `damage_profile_id` back to its clone-source vanilla id (`wt_authentic_pistol`->`shot_sniper`, `wt_priest_punch_buffed`->`light_blunt_smiter_stab`, `wt_brettsns_*`->source) before a CLIENT send whenever parity is not positively confirmed - catches leaks across the gate flip (mid-swing latched ids). Takes no toggle argument by construction (class 31 fix template; wire safety is never toggle-gated, issues 278/371). Host-side local dispatch is untouched (no wire; host runs wt).
- **Tooltips** for the three toggles now state the multiplayer constraint (auto-disable when a player without wt is present, auto re-enable when everyone has it).
- **Regression:** `wt_431_peer_parity_beacon_installed` (beacon installed, gated feature present, fail-safe posture + classifier asserts) and `wt_431_wire_floor_ungated` (marker, fallback map correctness, every fallback resolves in NetworkLookup, pure coercion helper takes only the parity flag) in `/wt_regression_test`.
- **Verify (REQUIRES 2 PLAYERS, one WITHOUT wt - this cannot reproduce solo):** see issue #431 test method. Solo smoke: load line `[wt:LOAD] v0.12.211-dev`, `/wt_regression_test` all-pass, brace/punch/Bret buffs still work solo (parity confirms itself sub-second with no other humans).

## 0.12.210-dev (2026-07-12) - Structural refactor (Phase 2 OOP split): the 3P anim-remap core extracted to `_wt_anim_remap.lua`, no behavior change

Continues the OOP decomposition (OOP_REFACTOR_PLAN WS5, PROJECT_STANDARDS §2.2a). Phase 2 extracts the **3P animation-remap CORE** - the machinery that makes a foreign weapon's 3P events resolve to clips the receiver's skeleton actually authors - into a single-responsibility `_wt_anim_remap.lua`. **Zero behavior change** - a verbatim function-bag move (byte-compared against the previous commit), hook set identical (lint: 19 files, 19 hooks, 0 duplicate/forward-ref/late-local). Entry `weapon_tweaker.lua` 7,230 -> 4,472 lines (-2,758); the new module is 2,845 lines.

- **What moved** (entry lines 359-3145, verbatim): the three redirect layers (`_anim_redirect` global renames, `_career_anim_redirect` career-prefix renames, `_suffix_career_map` suffix swaps + `_try_suffix_redirect`/`_safe_has_anim`); the per-weapon/template/key remap tables (`_3p_remap_*`, `_3p_template_remaps`, `_3p_key_remaps`) + their resolvers; the weak-keyed per-unit remap state (`_unit_state`/`_state_for`); the `Unit.animation_event` funnel hook; the two wield hooks (`SimpleInventoryExtension.wield` + husk) that populate the state; the anim-funnel commands (`/info`, `/animlog`, `/force3p`, `/force1p`); and the keep-previewer 3P pose resolver `_resolve_preview_wield_event`. Both remap-key namespaces (weapon-only `_3p_key_remaps` AND template-qualified `_3p_template_remaps`) moved together, as required.
- **Hot path stays local.** The funnel is per-event-hot, so the module keeps its own tables as file-local upvalues - the per-event path never indirects through `mod._wt`. The entry publishes the four handles the funnel reads (`feature_enabled`, `local_career_name`, `dbg`, `dev_anim_picker`, plus the pre-existing `MOD_VERSION`/`weapon_unlock_map`) onto `mod._wt` BEFORE the dofile; the module captures them as upvalues at load. `feature_enabled` + `_local_career_name` stay defined in the entry (generic player-state helpers).
- **Non-hot cross-module reads.** The module EXPORTS `mod._wt.safe_has_anim`/`.resolve_preview_wield_event`/`.unit_career_name`/`.unit_state`/`.suffix_career_map`/`.three_p_template_remaps`, which the entry re-localizes with byte-identical names so its stayed code is unchanged: the keep previewer (`MenuWorldPreviewer._spawn_item_unit`) calls the pose resolver + `_safe_has_anim`; the in-mission mesh-swap `spawn_inventory_unit` path reads `_unit_career_name`; the port-pipeline longbow template patchers still mutate the shared `_3p_template_remaps` table (same object, by reference); and the `/wt_regression_test` check bodies still probe `_unit_state`/`_suffix_career_map`.
- **Deliberately NOT extracted** (port-pipeline-coupled, deferred to Phase 3): the `wield_anim_career_3p` template patchers + `_WIELD_ANIM_CAREER_3P_PATCHES_BULK` application (the 3P render lever - do not reorder relative to template reads), the cross-character port pipeline (`spawn_inventory_unit`/`create_equipment` mesh swaps + package force-loads + previewer hooks), the per-frame grip offsets, the P0 crash guards (`link_units` filter, `create_equipment` career/`override_item_units` compensations - kept BYTE-INTACT), and the `AnimationSystem.anim_event_with_variable_float` crash guard (a self-contained anim-variable defence that does not consume the redirect layers).
- **Verify:** build OK (4 bundles); lint PASS (19 files, 19 hooks, 0 duplicate/forward-ref/late-local); module confirmed compiled into the bundle. In-game: load line `[wt:LOAD] v0.12.210-dev`; run `/wt_regression_test` (all prior checks present, incl. `anim_remap_per_unit` + `billhook_anim_remap_present` which probe the re-localized tables); equip a cross-character weapon (e.g. Brace of Pistols on Kruber, Longbow on Saltzpyre, Bardin billhook on non-Kruber) and confirm the 3P attack/wield anims still remap correctly for the local body AND remote husks; open the keep inventory previewer on a cross-character port and confirm the wield pose is still corrected; `/animlog` + `/force3p` still function.

## 0.12.209-dev (2026-07-12) - Structural refactor (Phase 1 OOP split): 4 concerns extracted from the god file, no behavior change

Pure structural decomposition of the 7,863-line `weapon_tweaker.lua` god file into single-responsibility `_wt_*` modules (OOP_REFACTOR_PLAN WS5, the event_tweaker/enemy_tweaker/cosmetics_tweaker PROJECT_STANDARDS §2.2a template). **Zero behavior change** - verbatim function-bag moves, log/command strings byte-identical, hook set identical (lint: 18 files, 19 hooks, 0 duplicate/forward-ref). The entry keeps byte-identical file-local aliases so every call site is unchanged. Cross-module state rides a new `mod._wt` namespace table (separate key from the established flat `mod._wt_*` fields, which are untouched).

- **New modules + a manifest.** Entry `weapon_tweaker.lua` 7,863 -> 7,226 lines (-637). Extracted:
  - `_wt_regression.lua` (52 lines) - the `/wt_regression_test` harness (`_RT_CHECKS` + `rt_register` + command). Loads FIRST (et `_et_regression` precedent) and exports `mod._wt.rt_register`; the ~30 check bodies stay inline in the entry next to the file-locals they probe, via `local _rt_register = mod._wt.rt_register`.
  - `_wt_availability.lua` (203 lines) - cross-character weapon availability control surface: `apply_weapon_unlocks` (can_wield strip/add), `patch_career_actions_on_weapons` (career-ability action injection), `clear_weapon_unlocks` / `clear_career_action_injections` (on_disabled revert), the `_kruber_removed_pairs` one-shot cleanup, and the shared `_career_action_injections` bookkeeping. Reads `mod._wt.weapon_unlock_map` / `.cwv_managed`.
  - `_wt_trait_pools.lua` (228 lines) - CW weapon-trait pool filtering (`_trait_pool_sources` + `apply_trait_filters` / `revert_trait_pools`, currently a retired no-op stub; exports + call sites kept so nothing dangles).
  - `_wt_diagnostics.lua` (308 lines) - leaf dump/probe commands `/sm_probe`, `/dump`, `/dump_actions`, `/dump_weapons`, `/wt_dump_wielded` + the wield-time weapon-data dump and its sole `SimpleInventoryExtension._wield_slot` hook_safe. All read engine globals only.
- **Deliberately NOT extracted this phase** (deferred to keep Phase 1 safe): the 3P anim-remap core (`Unit.animation_event` funnel + `_anim_redirect`/`_career_anim_redirect`/`_suffix_career_map` + `_unit_state`), the `wield_anim_career_3p` template patchers + cross-character port pipeline, the per-frame grip offsets, the P0 crash guards (`link_units` filter, `create_equipment` compensations), and the anim-funnel-coupled commands (`/info`, `/animlog`, `/force3p`, `/force1p`) + port-pipeline `/brace_to_repeater_*` - they read the entry's hot anim-remap file-locals. Big Rebalance stays its own on-ice module.
- **Verify:** build OK (4 bundles); lint PASS; command inventory conserved (12 total, no dup/loss); `/wt_regression_test` runs unchanged. In-game: load line `[wt:LOAD] v0.12.209-dev`, run `/wt_regression_test` (all prior checks present), `/dump` / `/dump_weapons` / `/sm_probe` still print, cross-character unlock a weapon and confirm it equips + its career ability still fires.

## 0.12.208-dev (2026-07-11) - Engine backlog P0 pass: BR flamethrower health-ext guard, create_equipment hook audit (dropper identified, external), hold-pose lint cleanup

Three items from `docs/engine/IMPROVEMENT_BACKLOG.md` (P0 rows owned by wt). None has its own GitHub issue; the backlog is the tracker.

- **[dormant] BR flamethrower cone: guarded the unguarded health-extension deref** (`weapon_tweaker_big_rebalance.lua:2444`). The vanilla-port `_select_targets` body did `ScriptUnit.extension(hit_unit, "health_system"):is_alive()` on broadphase-listed AI units; a unit mid-unregister (or without a health extension) makes `ScriptUnit.extension` silently return nil (`script_unit.lua:61-66`) and the `:is_alive()` deref crashes. Now fetched via `ScriptUnit.has_extension` + nil-test (sibling pattern `enemy_tweaker_big_rebalance.lua:473-474`); on a missing extension the unit still lands in `targets` exactly as before but is skipped for the `num_hit` cap count, with a `[wt:br_hooks]` pcall-printf diagnostic. **Zero runtime impact today:** the whole BR module is ON ICE (its `mod:dofile` is commented out at `weapon_tweaker.lua:88-89`, disposal pending user decision issue 433), so this rides along for an eventual BR revival. No `_rt_register` marker added on purpose - the module never loads, so a runtime marker test could only fail or permanently skip.
- **create_equipment hook audit (repo-wide): wt is clean; the career_name dropper is EXTERNAL Material Hijack.** Audited every `GearUtils.create_equipment` wrapper against the 12-param vanilla signature (`gear_utils.lua:7`, `career_name` last): wt (`weapon_tweaker.lua:3712/3751`), cosmetics (`cosmetics_tweaker.lua:5212/5229`), cwv (`:10615/10616`), ct (`:5794/5811`), ct_dev (`:6628/6645`), frozen tweaker (`tweaker.lua:175/177/220`), stale wt_dev clone (`:1805/1844`) ALL name and forward the full arity - no in-repo dropper. The dropper matching the historical crash-dump signature (career_name non-nil at wrapped frames, nil at the vanilla frame, `override_item_units` surviving) is **standalone Material Hijack**, whose wrapper names only 11 params and truncates the arg list at `override_item_units` (`Material-Hijack.lua:212/218`; the user's archived patched port inherited the same defect, `material_hijack_patched.lua:332/337`). Third-party code - not fixable here. **Consequence: wt's two downstream compensations (career_name recovery + `override_item_units` pre-resolve, `weapon_tweaker.lua:3712-3749`) are the operative defense and are deliberately KEPT**, contrary to the backlog row's "delete after fixing the dropper" - any peer running standalone MH re-introduces the drop. Audit results baked into `docs/engine/06_items_gear_and_husk_inventory.md` 5.5 and the backlog.
- **Hold-pose tuner: 12 SAVE-RESTORE `set_without_get` lint warnings fixed honestly** (`wt_dev_hold_pose.lua`). The 12 `mod:set("wt_dev_hp_rh/lh_...", 0)` writes in `/wt_dev_hp_reset` had no literal `mod:get` partners - reads went through concatenated keys (`"wt_dev_hp_"..p.."_offset_x"`), which the lint parses as the truncated literal `"wt_dev_hp_"`. Extracted a shared `_read_sliders(p)` helper that reads all six sliders per hand with LITERAL keys and rewired `_pose_is_default` / `_build_pose` / `_dump_snippet` through it. Identical values, one read path instead of three, and every reset key now has a greppable matching get. No suppression: the lint's dynamic-get escape hatch was not invoked.
- **In-game verify:** load line `[wt:LOAD] v0.12.208-dev`. Hold-pose: tune RH/LH sliders with live-apply on, `/wt_dev_hp_reset`, confirm pose returns to the baked grip and `/wt_dump_hold_pose` prints zeros. BR item is unverifiable in-game by design (module not loaded).

## 0.12.207-dev (2026-07-05) - CRASH FIX #362: create_equipment hook returned nil -> add_equipment fatal

**Crash console 2026-07-06-00.12.37 (guid ff863169):** picking up a debug-`/spawn`-ed `whale_oil_barrel` off the whaling map crashed at `simple_inventory_extension.lua:915 attempt to index local 'slot_equipment_data' (a nil value)`. Chain: the barrel's 3p unit (`wpn_whale_oil_barrel_01_3p`) is non-resident off-level -> cosmetics_tweaker skips its spawn (avoiding a C-assert) -> vanilla `GearUtils.create_equipment` indexes the nil unit and raises (`entity_manager2.lua:114`) -> **wt's create_equipment pcall caught it and `return nil`** -> vanilla `add_equipment` indexes that nil return UNGUARDED (`slot_equipment_data.master_item`/`.skin`, :876/:880) -> fatal.

- **wt's create_equipment hook now returns an empty `{}` stub instead of `nil`** on pcall failure (and `result or {}` on the success path). `add_equipment` completes -> the item equips-but-unrendered (all unit fields nil -> vanilla wield guards on `Unit.alive`) instead of crashing the game. The `[wt][ERROR] create_equipment CRASHED …` diagnostic line is unchanged. The old `return nil` (v0.12.77 #26, to keep a raise from killing sibling hooks) was the 'guard that delegates still crashes' class: it turned a caught error into a guaranteed downstream crash. This hardens EVERY create_equipment failure, not just this barrel.
- **Normal-play risk: low** — on the actual whaling map the package is resident and create_equipment succeeds; this needs a non-resident level-event unit (off-level `/spawn`). Deeper follow-up (force-load the package / block off-level level-event pickups) tracked in #362.

## 0.12.206-dev (2026-07-04) - Ship #301 dev status-tag pass (rider on 0.12.205 #319 anim work)

## 0.12.205-dev (2026-07-04) - #319 pipeline audit results: restore 5 dropped Kerillian billhook picks (#290 residual), crowbill pick corrections, #286 Greataxe wield fix

Full config-to-bake audit for #319 ("failing to get animations properly from config"): every `wt_dev_anim_p_*` key across all 7 `user_settings` configs on disk (5 Downloads backups, the pre-wipe backup, the live config) was parsed and diffed against the v0.12.203/.204 baked R-tables. **Result: of 764 distinct real event-picks, 746 were already faithfully honored.** The gaps, all fixed or explained here:

- **RESTORED: Kerillian billhook (`wh_2h_billhook`), 5 tester picks dropped by the v0.12.203 bake** — the one true residual of the #290 two-namespace bug. The tester's Kerillian billhook picks live in the TEMPLATE-QUALIFIED namespace; the v0.12.203 bake merged both namespaces for es_/wh_ but read Kerillian only from weapon-only, so `R.two_handed_billhooks_template` got no `we_` table and those 5 events (charge_down, charge_stab, heavy_down, heavy_left, stab_02) fired raw on Kerillian's spear SM (wield is `to_spear`) — wrong/absent swings. Now baked verbatim from `user_settings(4).config`; values are identical to the confirmed-working `es_` set.
- **CORRECTED: crowbill `attack_swing_up_left` target** in both `one_handed_crowbill.dr_` and `._default`: the table had `attack_swing_left_diagonal`; the tester's pick in ALL 7 configs is `attack_swing_left`. Bake is a faithful image; corrected to the pick.
- **#286 (shipped in this build, staged earlier): Bardin Greataxe on Saltzpyre** wields as WP Greathammer (`to_2h_hammer_priest`) instead of Greatsword — `two_handed_axes_template_1` was the lone 2H-blunt template still routing wh_ to `to_2h_sword` (sibling template_2 and every other 2H-blunt already used hammer_priest).
- **Explained, no code change — "boot re-apply: 13 stored pick(s) applied" is EXPECTED, not pick loss.** `reapply_stored_picks()` iterates only the LIVE picker rows (current receivers × current weapon sets), not the config store. The ~150 other real picks in the live config belong to already-BAKED weapons, which apply from the static R-tables at file load and are invisible to that counter. Audit also catalogued every silent-drop point in the pick lifecycle (10 identified; see #319 comment) — the actionable ones are fixed above.
- **Deliberately NOT wired: Kruber `dr_dual_wield_axes` local picks (13 events in pre-wipe + live configs).** That pair — like Kruber Axe & Falchion (#319 part 1, fixed in cwv v0.1.362-dev) — is CWV-managed (`_cross_access_action_remap`); wiring a wt es_ bake would double-remap against CWV's hook. The stale picks predate the CWV migration.
- Doc fix: stale `wt_port_status.lua` comment claiming #180/#182 were still in `_NEEDS_ANIMS` (both baked + confirmed since v0.12.188).
- **In-game verify:** (1) Kerillian + Billhook: charged stab and both heavies play spear-vocabulary swings, no frozen/foreign poses. (2) Saltzpyre + Bardin Greataxe: body holds the two-handed WP greathammer stance, not the greatsword stance. (3) Bardin or Kerillian + Crowbill: L2-position light plays a horizontal left swing. Load line: `[wt:LOAD] v0.12.205-dev`.

## 0.12.204-dev (2026-07-04) - Localization: applied dev status-tag doctrine (#301) — hand toggles + emitter normalization + Big Rebalance issue-tag

Three-part #301 pass across wt's option-title surface:

**1. Hand-typed feature toggles (6, all `[working]`):** `weapon_overrides` (Weapon Tweaks group), `authentic_brace_of_pistols`, `wt_brett_sword_shield_buff`, `moonfire_aoe_revert`, `wt_priest_punch_buff`, `enable_dev_anim_picker` — established features/tools with no open issue mapping to the toggle itself. (#131 Moonfire-extra-shots explicitly rules out `moonfire_aoe_revert` as the cause; picker-internal issues #108/#168/#184/#196/#197/#248/#290 concern dynamic dev-tooling labels or the computed availability rows, not the picker enable toggle.)

**2. Weapon-Availability runtime emitter normalized to #301 vocab.** The ~939 `unlock_*` availability rows carry COMPUTED tags applied at load by `wt_port_status.lua`'s `M.tag`; that loop strips any leading `[...]` and re-prepends, so hand-tagging those rows is futile by design (documented doctrine exception — the emitter OWNS them and keeps them in lockstep with the 3P Anim Picker). Its emitted vocabulary was **normalized from Title Case to the #301 lowercase forms**, keeping the redirect detail: `[Working]`→`[working]`, `[Untested]`→`[untested]`, `[Needs Offsets]`→`[needs offsets]`, `[Needs Animations → X]`→`[needs animations → X]`. Changed in lockstep: `wt_port_status.lua` `M.tag` returns + its legend docstring; the localization consumer's `tag == "[needs animations]"` compare + `"[needs animations → "` splice (`weapon_tweaker_localization.lua`); the vocab-declaration comments in the loc file and `weapon_tweaker_data.lua`; and the one reader-facing "the Availability tag reads `[working]`" line in `ANIMATION_COVERAGE.md`. No `_rt_register` regression marker references these literals (verified by grep); historical CHANGELOG/DECISIONS prose left untouched.

**3. Big Rebalance block tagged with its governing issue.** All **149 `br_*` option titles** (master + category groups + leaf toggles) now carry **`[Issue 321]`** — the tracker for the block being inert since `bt`/`buff_tweaker`'s retirement (they gate on `is_br_active`). No per-toggle status guessing; the governing-issue tag is intentional. The three true-flight toggles (`br_hook_trueflight_start`, `br_hook_trueflight_fire`, `br_we_ww_trueflight`) carry **`[Issue 321 & 74]`** (#74 = BR true-flight reimpl divergences, `deferred`). `br_*` keys are not `^unlock_`, so the runtime loop leaves these hand tags intact. `br_*_description`/`_tooltip` entries left untagged (not option titles).

**Left untagged (documented exceptions):** ~50 Weapon-Availability navigation groups (`weapon_availability`, `char_*`, `<char>_melee/ranged_group`, `melee_*`/`ranged_*` career groups) — pure container folders spanning mixed-status children, no single feature status applies.

## 0.12.203-dev (2026-07-03) - FIX regression: v0.12.201 dropped ~30 Kruber/Saltzpyre 3P picks (only Kerillian baked). Regenerate a FAITHFUL image of the tester config for all 3 receivers

The tester reported that on **Kruber**, almost no non-Saltzpyre weapon had proper 3P animations, and polearms were still T-posing. They were right - v0.12.201 mis-baked their data.

- **Root cause (self-inflicted regression, v0.12.201):** the picker stores picks under TWO key namespaces in `user_settings.config`. The CURRENT picker writes **weapon-only** keys (`wt_dev_anim_p_<receiver>_<weapon>_ev_<event>`, since `port_id = "p_"..r.."_"..weapon_key`, `wt_dev_anim_picker.lua:1353`). An **older** picker wrote **template-qualified** keys (`..._<weapon>_<template>_ev_<event>`). The tester tuned **Kerillian** in the current (weapon-only) picker but **Kruber and Saltzpyre** in the legacy (template-qualified) one. v0.12.201's bake read ONLY the weapon-only namespace, so it saw Kerillian's 33 ports as "complete" (its CHANGELOG even claims "all 35 ports were complete") and **silently dropped ~30 Kruber/Saltzpyre event-picks** across 10 templates - including the **billhook polearm on Kruber**, **dual axes**, crowbill, flaming flail, and the Sienna staves. Those ports had no `es_`/`wh_` redirect at all → they T-posed.
- **Fix:** regenerated the ENTIRE cross-character bake do-block as a deterministic, faithful image of `Downloads/user_settings(4).config` for all three receivers, **merging both namespaces per receiver** (weapon-only preferred on the single conflict; Kerillian left weapon-only-only). Coverage now: `we_` (Kerillian) 33 templates, `es_` (Kruber) 21, `wh_` (Saltzpyre) 20. The `we_` output was re-validated **byte-for-byte identical** to the v0.12.201 bake (338 event-pairs, 0 diff), so Kerillian is provably unchanged; only the missing Kruber/Saltzpyre picks were added. Every already-baked `es_`/`wh_` value was verified to already match the tester config (0 stale).
- **Safety:** confirmed NO `es_` redirect lands on a Kruber-native template - all 21 `es_` redirects are on foreign-owned templates; Kruber-native weapons (greatsword, greathammer, halberd, executioner, bastard, both Bretonnian sword & shields) keep `es_ = false` and play native, untouched.
- **Generator:** `scratchpad/gen_bake_v4.ps1` (parse both namespaces → merge per receiver → emit) + `validate.ps1` (we_ byte-parity gate). The two-namespace split is the trap that must not be repeated on the next bake.
- **In-game verify:** on Kruber, wield the ported billhook (polearm), Bardin's dual axes, Sienna's flaming flail / staves, and Bardin's crowbill - swing/charge animations should now play instead of T-posing. Kerillian ports should be unchanged from v0.12.201. Load line: `[wt] Weapon Tweaker v0.12.203-dev`.

## 0.12.202-dev (2026-07-03) - Stop `_dbg_alert` chat spam: route diagnostics to log-only printf (Issue #240 / BUG_CLASSES §17B)

The user reported "a bunch of weapon tweaker warnings" in chat. The newest log (`console-2026-07-03-21.30.34-...`) carried ~31 identical `[MOD][wt][WARNING] [wt:attach_probe] MISSING NODE on body ... source=a_unwielded_staff -- engine fatal expected` lines, one per inventory-preview refresh with a staff sitting in a Kruber career's ranged slot (the staff-on-Kruber availability from v0.12.198).

- **Root cause (chat spam):** `_dbg_alert` routed through `mod:warning`, which posts to CHAT by default (VMF `warning` = mode 3, `send_to_chat = mode >= 2`). This is BUG_CLASSES.md §17B / Issue #240 - the same class the et v0.7.25-dev fix flagged for wt on its watch list. **Fix:** `_dbg_alert` now writes log-only via pcall-guarded engine `printf` (`weapon_tweaker.lua`), mirroring et #240. printf always lands in `console-*.log` even with mod-logging off, and never touches chat. Every wt `_dbg_alert` site (the `[wt:attach_probe]`, the `[wt:tpl_patch] skip` traces, the sp-longbow abort) is a routine diagnostic, none user-actionable, so all correctly become log-only. Marker `mod._wt_alerts_log_only_marker` + the `dbg_helpers_two_channel` regression test now assert the routing.
- **The `a_unwielded_staff` node is NOT a crash** (verified, not silenced): the universal `GearUtils.link_units` guard (`WT_LINK_UNITS_NODE_GUARD_MARKER`) drops any link whose source/target node is missing on the body BEFORE vanilla's `Unit.node` (`gear_utils.lua:297-298`) can engine-fatal, on every spawn path (`GearUtils.link` -> `link_units` via the table, `gear_utils.lua:288-290`). That is why ~31 probe fires produced no crash and no crash dump. The probe's "engine fatal expected" wording was a **false alarm obsoleted by the later guard**, so the `[wt:attach_probe]` line is downgraded from `_dbg_alert` to `_dbg` (debug-gated) and reworded to "neutralized by link_units guard, not fatal".
- **Follow-up filed:** the probe firing exposes a cosmetic boot-substitution gap (a holstered staff on a Kruber ranged slot may not render on the hip, since the guard drops the link rather than substituting `j_hips`). No crash. Tracked as a separate low-priority GitHub issue; not fixed here to keep this change focused.
- **In-game verify:** load the keep with a staff equipped on a Kruber career (e.g. Deepwood Staff on Mercenary) and open the inventory - chat should no longer fill with `[wt:attach_probe]` / MISSING NODE warnings.

## 0.12.201-dev (2026-07-03) - BAKE the tester's 3P picks: Kerillian batch-1 (33) + Saltzpyre Executioner + Kruber Skullsplitter & Tome

The tester (remote) fully tuned every `[Needs Animations]` port across all three receiver pickers. Their persisted picks (`Downloads/user_settings(4).config`, 2026-07-03) are baked here verbatim - all 35 ports were complete (per-attack pick set == source-attack count for every one).

- **Baked 35 ports career-scoped into `_3p_template_remaps`** (`weapon_tweaker.lua`), appended as a post-definition assignment block (mirrors the existing longbow-port block) so each new `we_`/`wh_`/`es_` entry MERGES into any existing `es_`/`wh_` literal entry without disturbing it:
  - **Kerillian batch-1 (33 ports, `we_`)**: `es_2h_hammer`, `wh_2h_hammer`, `dr_2h_cog_hammer`, `dr_2h_pick`, `bw_ghost_scythe`, the 5 `bw_skullstaff_*`, `bw_necromancy_staff`, `bw_deus_01` (-> Elf Glaive); `es_2h_sword_executioner`, `es_bastard_sword` (-> Elf 2H Sword); `wh_fencing_sword`, `bw_1h_flail_flaming`, `bw_dagger`, `bw_flame_sword` (-> Elf 1H Sword); `wh_1h_hammer`, `dr_1h_hammer` (-> Elf 1H Axe); `es_mace_shield`, `es_sword_shield`, `es_sword_shield_breton`, `wh_flail_shield`, `wh_hammer_book`, `wh_hammer_shield`, `dr_shield_axe` (-> Elf Spear & Shield); `wh_dual_hammer`, `dr_dual_wield_axes`, `dr_dual_wield_hammers` (-> Dual Swords); `es_dual_wield_hammer_sword`, `wh_dual_wield_axe_falchion` (-> Sword & Dagger); `dr_1h_throwing_axes` (-> Elf Javelin).
  - **Saltzpyre `es_2h_sword_executioner` (`wh_`)**: Kruber Executioner Sword -> Saltzpyre 2H Sword (#160).
  - **Kruber `wh_hammer_book` (`es_`)**: Skullsplitter & Tome tuned as a full anim remap (1H Skullsplitter vocab), not the mesh-swap the #181 note anticipated.
- **Native owners stay untouched**: every baked template sets the source weapon's owner prefix to `false` (guarded `or false`, never clobbering an existing table). Two templates are shared across receivers and now carry three keys each: `two_handed_swords_executioner_template_1` = `{ es_ = false, we_, wh_ }`; `one_handed_hammer_book_priest_template` = `{ wh_ = false, es_, we_ }`. `dual_wield_axes_template_1` deliberately gets NO `dr_ = false` (its Bardin remap is per-career `dr_ironbreaker/ranger/engineer`; a `dr_` prefix would shadow them).
- **Status lockstep** (`wt_port_status.lua`): all 35 moved `_NEEDS_ANIMS` -> `_CONFIRMED` (tag flips to [Working]); the Kerillian/Saltzpyre/Kruber `_NEEDS_ANIMS` gates are now empty. 3P-only (consumed at the `Unit.animation_event` hook); identity picks are harmless re-fires; `__unset__` picks were omitted (fall through to native).
- **Queued Saltzpyre batch-2 into the dev 3P Anim Picker (11 ports)** so the remote tester has the next group to tune. Wired into `_SALTZ_WEAPON_SET` / `_SALTZ_WEAPON_TEMPLATE` / `_SALTZ_WEAPON_ATTACKS` (`wt_dev_anim_picker.lua`, source-attack lists copied verbatim from the existing `_KERI_WEAPON_ATTACKS` / Kruber `_WEAPON_ATTACKS` entries) + `_NEEDS_ANIMS.saltzpyre` (`wt_port_status.lua`), grouped by SET:
  - **WP Greathammer (SET A)**: `es_2h_hammer`, `dr_2h_cog_hammer`, `dr_2h_pick`, `bw_1h_mace`, `bw_ghost_scythe`.
  - **WP Dual Hammers (SET B)**: `dr_dual_wield_hammers`.
  - **2H Sword (SET G)**: `es_bastard_sword`.
  - **Dual Axe & Falchion (SET C)**: `es_mace_shield`, `es_sword_shield`, `es_sword_shield_breton`, `dr_shield_axe` (shield ports — the right-hand weapon is the tunable render; the shield offhand model is a separate later pass). Reuses the existing A/B/C/G `_SALTZ_SET_VOCAB`; no wield-patch changes (every target already has a `wh_captain/bountyhunter/zealot` redirect in `_WIELD_ANIM_CAREER_3P_PATCHES_BULK`). Pure picker wiring — nothing baked.
- **Lockstep picker cleanup**: emptied the now-stale baked tables to keep the picker gates in sync — Kerillian batch-1 (`_KERI_WEAPON_SET/_TEMPLATE/_ATTACKS` -> `{}`, `_KERI_SET_LABEL`/`_KERI_SET_VOCAB` left intact), the Saltzpyre Executioner (`es_2h_sword_executioner` removed), and Kruber `wh_hammer_book` (removed from the Kruber `_WEAPON_SET`/`_TEMPLATE`/`_ATTACKS`; `_SET_LABEL.F`/`_SET_VOCAB.F` left defined).

## 0.12.200-dev (2026-07-02) - Fix Deepwood Staff hard crash on non-elf wield (#236)

Equipping the newly-available Deepwood Staff on Kruber crashed to desktop with Script Error `ep_r_index` (`staff_life.lua` `init_state_data`). Cause: the Deepwood Staff is the only staff whose first-person wield/targeting effect spawns a vine finger-trail by resolving the right-hand finger nodes `ep_r_index/middle/ring/pinky/thumb` on the wielder's first-person mesh. Those nodes exist only on the elf first-person rig, so `Unit.node()` hard-crashes (C-level, bypasses the wield hook's pcall) on any non-elf body - Kruber, and the pre-existing Saltzpyre ports too.

- **Wrapped `staff_life`'s `synced_states.wielding.enter` and `.targeting.enter`** with a `Unit.has_node` guard (`weapon_tweaker.lua`): when the local player's first-person mesh lacks `ep_r_index`, state_data is initialised safely (empty `particle_ids`, timer set) and the finger-particle spawn is skipped; the staff otherwise wields normally, just without the elf vine effect that cannot attach to non-elf hands.
- **No-op for the native elf wielder**: Kerillian's rig has the nodes, so the guard falls through to the original `enter` byte-for-byte. First-person VFX only - no animation, model, or third-person change. Idempotent (`staff_life` and `staff_life_vs` share one `synced_states` table via shallow clone, so one wrap covers both).
- One guard fixes both the new Kruber availability and the latent crash on the existing Saltzpyre ports.

## 0.12.199-dev (2026-07-02) - Weapon Availability: consistent source-character row order (#179)

The Weapon Availability rows within each career were only unevenly ordered - some groups were grouped by source character, others drifted, and the runtime status-tag prefix ([Working] / [Untested] / [Needs Animations]) appeared to be driving the sort. Rows now sort deterministically by source character, never by tag.

- **Added one central normalization pass** at the end of `weapon_tweaker_data.lua` that reorders every `melee_<career>` / `ranged_<career>` leaf group's `unlock_<career>_<weapon>` checkboxes by **source character in the fixed roster order Kruber, Bardin, Saltzpyre, Kerillian, Sienna** (weapon_key prefix `es_`, `dr_`, `wh_`, `we_`, `bw_`), then alphabetically by weapon_key within each source character.
- **Sorts on the weapon_key only, never the localized label**, so the status tag (applied later in the localization table) can no longer influence row order - the reported "tags messing up the sort" bug.
- Single pass over the `weapon_availability` subtree only; every `setting_id` and `default_value` is unchanged, so `widget_unlock_map_consistency` stays green and no stored setting is affected. Future ports auto-sort without hand-ordering.

## 0.12.198-dev (2026-07-02) - Deepwood Staff now available on Kruber

Kerillian's **Deepwood Staff** (`we_life_staff`, Sister of the Thorn's life staff) was reachable on Kerillian and Saltzpyre careers but had been withheld from all four Kruber careers ("pending user decision"), so it never appeared in Kruber's Weapon Availability menu and could not be equipped or tested. Per user request 2026-07-02 it is now wired for Kruber the same way `we_javelin` already was.

- **Added `we_life_staff` to all four Kruber careers' unlock lists** (`wt_unlock_data.lua`): `es_mercenary`, `es_huntsman`, `es_knight`, `es_questingknight`.
- **Added the four companion Availability widgets** (`unlock_es_<career>_we_life_staff`, `weapon_tweaker_data.lua`) so the `widget_unlock_map_consistency` regression check stays green, plus the four **"Kerillian: Deepwood Staff"** loc labels (`weapon_tweaker_localization.lua`).
- **Extended the `staff_life` wield patch** (`wt_wield_patches.lua`) with the four Kruber careers -> `to_2h_hammer`, matching every other Sienna/elf staff port onto Kruber's body (Greathammer two-handed wield/idle vocab). The staff renders on Kruber immediately.
- Status: flagged **[Untested]** in the Availability menu (already present in `wt_port_status._UNTESTED.kruber`); not added to the dev 3P Anim Picker yet - the shared staff wield source renders it out of the box, per-attack 3P tuning is a follow-up if wanted.

## 0.12.197-dev (2026-07-01) - Settings menu: sort the Weapon Tweaks group A-Z

Settings-menu organization pass. No gameplay, setting, or widget changes; every `setting_id`, default, `range`, and tooltip text is untouched.

- **Sorted the four toggles in the "Weapon Tweaks" (`weapon_overrides`) group A-Z by display label** (`weapon_tweaker_data.lua`): Authentic Brace of Pistols, Bretonnian Sword and Shield buff, Moonfire Bow, Warrior Priest punch. Previously accretion-ordered. Only the row order changed; the `setting_id` multiset is identical.
- **Colocated the `wt_brett_sword_shield_buff` localization entries with the rest of the `weapon_overrides` block** and re-sorted that block A-Z to match the widget order (`weapon_tweaker_localization.lua`). The brett label/tooltip had been sitting alone in the top-of-file "Top-level groups" header area. Pure file-hygiene move; VMF resolves by key, so rendering is unchanged, and the `mod._wt_loc_raw` publication + dev-module loc merge downstream are untouched.
- **Top-level group order verified already A-Z** ("Weapon Availability" < "Weapon Tweaks"); the dev **3P Anim Picker** and hold-pose tools stay last (dev-tooling-last convention, mirrors `enable_debug_logging`). The per-weapon Availability tree keeps its deliberate v0.12.194 source-character grouping (#179).

## 0.12.196-dev (2026-07-01) - Wire up the Bretonnian Sword & Shield buff tooltip

The `wt_brett_sword_shield_buff` checkbox never showed its description: the widget had no `tooltip` field, so the settings menu auto-resolved `wt_brett_sword_shield_buff_description` (which does not exist) while the text lived under `..._tooltip`. The widget now passes `tooltip = "wt_brett_sword_shield_buff_tooltip"` explicitly (`weapon_tweaker_data.lua`). No key renames; no other changes.

## 0.12.195-dev (2026-07-01) - Localization fixes + player-facing option descriptions

Menu-text cleanup pass. No gameplay, setting, or widget changes; every setting_id, default, and range is untouched.

- **Fixed two option tooltips that were being localized twice** (once eagerly in code via `mod:localize(...)` in the widget's `tooltip` field, then again by the settings menu at build time), which made them render wrapped in `<>`. The dev **3P Anim Picker** master toggle (`enable_dev_anim_picker`, `weapon_tweaker_data.lua`) and the picker's per-attack dropdowns (`wt_dev_anim_attack_tooltip`, `wt_dev_anim_picker.lua`) now pass their loc keys as raw strings so the menu localizes them exactly once. The one correct eager-localize (`description = mod:localize("mod_description")`) was left as-is.
- **Rewrote every option description and tooltip in plain, player-facing English** (`mod_description`, the `weapon_overrides` / `authentic_brace_of_pistols` / `wt_priest_punch_buff` / `moonfire_aoe_revert` / brett-buff tooltips, all Big Rebalance `_description` keys, and the dev-picker tooltips), dropping internal terms (hooks, templates, anim events, profile names, mod-ids) in favor of what the option does in-game. Max two sentences each.
- **Removed leftover non-ASCII / angle-bracket characters from a few menu labels**: three Big Rebalance titles used a literal `->` arrow (now "to"), one dev-picker dropdown option used an em dash (now a hyphen), and the moonfire tooltip's `>` submenu path was reworded.
- **Key cross-check**: verified all 1145 widget `setting_id`s in `weapon_tweaker_data.lua` (and the dev-picker's programmatically generated group/dropdown titles) resolve to a loc key. No keys were missing; none added. Flagged one likely-orphaned key (`wt_brett_sword_shield_buff_tooltip`) whose widget auto-resolves the `_description` suffix, not `_tooltip` — left as-is per the no-rename rule.

## 0.12.194-dev (2026-07-01) — Availability menu source-character ordering (#179) + Executioner Sword on Saltzpyre picker (#160)

Two fixes plus a batch of stale-issue verifications.

- **#179 — Weapon Availability menu now groups every career's rows by SOURCE character in the fixed order Kruber, Bardin, Saltzpyre, Kerillian, Sienna** (weapon-key prefix es_, dr_, wh_, we_, bw_). Previously the ordering was inconsistent: each receiver listed its OWN character's weapons first, and the Saltzpyre careers (wh_captain / wh_bountyhunter / wh_zealot) were badly interleaved (e.g. `wh es we bw es dr we bw es dr we`). Reordered the `unlock_*` checkbox toggles inside every `melee_*` / `ranged_*` group in `weapon_tweaker_data.lua` to the fixed source-character order (stable within each source block, so existing within-block order is preserved). No toggle was added, removed, or re-defaulted — the setting_id multiset is byte-identical, only the row order changed. Also removed 12 stale historical batch-annotation comments (`-- Sienna batch D`, `-- Shield-combos override …`, `-- Batch E remaining …`) that were splitting the Saltzpyre lists; the shield-routing fact they noted is authoritative in `wt_wield_patches.lua`.
- **#160 — added Kruber's Executioner Sword (`es_2h_sword_executioner`) to the Saltzpyre side of the dev 3P Anim Picker** for per-attack tuning. It already renders as Saltzpyre's 2H Sword via the existing `to_2h_sword` wield redirect (`two_handed_swords_executioner_template_1` → wh_* in `wt_wield_patches.lua`); this adds the picker surface. New SET G ("2H Sword") in `_SALTZ_SET_LABEL` / `_SALTZ_SET_VOCAB` with `two_handed_swords_template_1`'s 3P vocab (that template carries zero `anim_event_3p` overrides, so 3P == `anim_event` names, #196-safe), plus the port in `_SALTZ_WEAPON_SET/_TEMPLATE/_ATTACKS` (`wt_dev_anim_picker.lua`) and a `_NEEDS_ANIMS.saltzpyre` entry (`wt_port_status.lua`). Dev-tool only, 3P-only; 1P untouched. Tune → bake in a later pass.

**Verified already-fixed (no code change this version; confirmed present in source with their regression tests, awaiting in-game re-confirmation):** #201 Deepwood Staff crash removal (v0.12.189, test `no_redundant_bardin_1h_on_saltzpyre` sibling area / `we_life_staff` gone from the 7 non-Kerillian lists), #195 Necromancer Staff soul_rip FX force-load (v0.12.179, test `necromancer_fx_package_resident_if_dlc`), #187 redundant Bardin 1H Axe/Hammer removed from Saltzpyre (v0.12.173, test `no_redundant_bardin_1h_on_saltzpyre`), #197 localize-flood fix reads the raw loc table (v0.12.183, test `wt_loc_raw_published`). #159 picker localized-name display shipped v0.12.178 (test `dev_picker_names_localized`); new code in this version follows the localized-name-comment convention.

## 0.12.193-dev (2026-07-01) — Dev 3P Anim Picker: add Kerillian as a third receiver (33 cross-character ports, 8 SETs)

Adds **Kerillian** (all four elf careers — Waywatcher / Handmaiden / Shade / Sister of the Thorn) to the dev **3P Anim Picker**, alongside the existing Kruber + Saltzpyre receivers, so the "next group" of cross-character melee weapons rendered on Kerillian's body can be tuned per-attack in-game. **Setup only** — no bakes, no `_3p_template_remaps` changes; the user tunes, then a later pass bakes. **3P-only** throughout; 1P never touched. Membership = every cross-character MELEE port (non-`we_` key) that appears in a `we_*` unlock list, is not already `_CONFIRMED.kerillian`, and has a `we_*` wield-redirect target in `wt_wield_patches`. Mirrors the Saltzpyre picker construction exactly (`_KERI_*` tables + `_RECV.kerillian` + `"kerillian"` in `_RECEIVERS`; move-label maps empty). New `_NEEDS_ANIMS.kerillian` bucket in `wt_port_status.lua` so the Weapon Availability menu tags them `[Needs Animations → <SET>]`.

Each SET's dropdown vocab is the Kerillian-native target template's `anim_event_3p` column (fallback `anim_event` where no `_3p`) — the 3P events the elf body actually authors (#196). Only `1h_axes_wood_elf` diverges (`attack_swing_up` → `attack_swing_up_left`), folded into SET D.

- **SET A — Elf 2H Axe/Glaive** (`to_2h_axe_we`, 12): es_2h_hammer, wh_2h_hammer, dr_2h_cog_hammer, dr_2h_pick, bw_ghost_scythe, bw_skullstaff_beam, bw_skullstaff_fireball, bw_skullstaff_flamethrower, bw_skullstaff_geiser, bw_skullstaff_spear, bw_necromancy_staff, bw_deus_01 (staves render as the 2H glaive)
- **SET B — Elf 2H Sword** (`to_2h_sword_we`, 2): es_2h_sword_executioner, es_bastard_sword
- **SET C — Elf 1H Sword** (`to_1h_sword`, 4): wh_fencing_sword, bw_1h_flail_flaming, bw_dagger, bw_flame_sword
- **SET D — Elf 1H Axe** (`to_1h_axe`, 2): wh_1h_hammer, dr_1h_hammer (vocab carries the #196 `attack_swing_up`→`attack_swing_up_left` 3P divergence)
- **SET E — Elf Spear & Shield** (`to_1h_spear_shield`, 7): es_mace_shield, es_sword_shield, es_sword_shield_breton, wh_flail_shield, wh_hammer_book, wh_hammer_shield, dr_shield_axe
- **SET F — Dual Swords** (`to_dual_swords`, 3): wh_dual_hammer, dr_dual_wield_axes, dr_dual_wield_hammers
- **SET G — Sword & Dagger** (`to_dual_sword_dagger`, 2): es_dual_wield_hammer_sword, wh_dual_wield_axe_falchion
- **SET H — Elf Javelin** (`to_javelin`, 1): dr_1h_throwing_axes

**Firearms excluded** (would route to `to_repeating_crossbow_elf`): wh_brace_of_pistols, wh_crossbow, wh_deus_01, wh_repeating_pistols, es_blunderbuss, es_handgun, es_repeating_handgun, dr_deus_01, dr_drake_pistol, dr_drakegun, dr_rakegun, dr_steam_pistol, dr_crossbow — the elf repeating crossbow authors only `attack_shoot`/`to_zoom` in 3P, so there's no meaningful per-attack tuning surface (same rationale the Kruber/Saltzpyre pickers used to exclude firearms).

**Skipped** (no `we_*` wield-redirect target): es_1h_mace (`one_handed_hammer_template_1`), es_longbow (`longbow_empire_template`), wh_crossbow_repeater (`repeating_crossbow_template_1`, `es_`-only) — no elf redirect.

## 0.12.192-dev (2026-07-01) — Fix longbow zoom/aim on Kruber's non-Huntsman careers (#210 follow-up)

The v0.12.191 fix restored the native Huntsman longbow charge, but it also stopped the aim/zoom working when the Empire longbow is used on Kruber's OTHER careers (Mercenary/Foot Knight/Grail Knight), where it's a cross-career unlock. The zoom is the `action_two` aim (`anim_event = "draw_bow"`); on those cross-career bodies the native `draw_bow` doesn't drive the aim, so it must render via the universal `to_zoom` (as it did before .191). Fixed by keying the runtime remap on FULL career name: `es_huntsman` keeps native `draw_bow`; `es_mercenary`/`es_knight`/`es_questingknight` (and `wh_` Saltzpyre) map the aim to `to_zoom`. Native Huntsman unchanged.

## 0.12.191-dev (2026-06-30) — Fix native longbow charge/draw animation broken by the longbow→crossbow patch (#210)

Charging Kruber's own Empire longbow (and Kerillian's elf longbow) stopped animating. Cause: the Saltzpyre longbow→crossbow support (`_patch_longbow_empire_template_for_saltzpyre` / `_patch_longbow_template_1_for_saltzpyre`) overwrote `anim_event_3p` on the **shared** longbow templates **globally** — remapping `draw_bow` → `to_zoom` (crossbow aim) for every career, so the native wielder's draw fired a crossbow event that its body couldn't play. Fixed by moving the per-action crossbow remap off the shared template and into the **runtime career-scoped** `_3p_template_remaps.<template>.wh_` (Saltzpyre-only), with `es_`/`we_` marked native (`= false`). The career-scoped *wield* override is unchanged. Kruber/Kerillian native longbows keep their own `draw_bow`/`attack_shoot_fast`; Saltzpyre's crossbow swap still remaps. 1P untouched.

## 0.12.190-dev (2026-06-30) — Rename "Weapon Overrides" menu section to "Weapon Tweaks"

Display-label only — the `weapon_overrides` group now reads **"Weapon Tweaks"**. setting_id unchanged (no settings reset).

## 0.12.189-dev (2026-06-30) — Fix Deepwood Staff (we_life_staff) hard-crash on non-Kerillian careers (#201)

The Sister of the Thorn's Deepwood Staff (`we_life_staff`, `staff_life`) hard-crashed on wield when equipped on Kruber (and Saltzpyre): `staff_life.lua` `init_state_data` reads Kerillian-body finger nodes (`ep_r_index` etc.) via `Unit.node`, a C-level fatal (c_api_unit.cpp:74) that bypasses pcall — those nodes don't exist on non-Kerillian bodies. The staff's whole magic rig is finger-node-bound, so it can't render off-Kerillian. Removed `we_life_staff` from the 7 non-Kerillian career unlock lists (Kruber ×4 + Saltzpyre ×3) plus their `_data.lua` widgets and loc keys. Kept native on Sister of the Thorn (we_thornsister).

## 0.12.188-dev (2026-06-30) — Bake the dev-picker 3P picks: 10 Kruber + 17 Saltzpyre cross-character ports flip to [Working]

The user's confirmed dev 3P Anim Picker picks (from `user_settings(2).config`) are now **baked** career-scoped into `_3p_template_remaps` (`weapon_tweaker.lua`) so the animations ship to everyone — no dev toggle needed. Each baked weapon moved from `_NEEDS_ANIMS` → `_CONFIRMED` in `wt_port_status.lua` (Availability tag flips to **[Working]**) and was deleted from the picker tables (`_WEAPON_SET`/`_WEAPON_TEMPLATE`/`_WEAPON_ATTACKS` for Kruber, the emptied `_SALTZ_*` tables for Saltzpyre). **3P-only**, career-scoped (Kruber = `es_`, non-WP Saltzpyre = `wh_`); native owners (`bw_`/`we_`/`es_`/`wh_` = `false`) play untouched. 27 career-sub-keys added/replaced total.

**Kruber (`es_`, 10 ports):**
- `dr_2h_cog_hammer` → `two_handed_cog_hammers_template_1` (16 picks; **re-tuned**, #182 — replaces the v0.12.151 3-pick identity bake).
- `wh_2h_hammer` → `two_handed_hammer_priest_template` (14 picks; **re-tuned**, #180 — replaces the v0.12.151 bake).
- `wh_fencing_sword` (Rapier) → `fencing_sword_template_1` (7 picks; new, #178).
- `bw_deus_01` → `bw_deus_01_template_1` (4 picks); `bw_necromancy_staff` → `staff_death` (6 picks); `bw_skullstaff_beam` → `staff_blast_beam_template_1` (5 picks); `bw_skullstaff_fireball` → `staff_fireball_fireball_template_1` (4 picks); `bw_skullstaff_flamethrower` → `staff_flamethrower_template` (4 picks); `bw_skullstaff_geiser` → `staff_fireball_geiser_template_1` (4 picks); `bw_skullstaff_spear` → `staff_spark_spear_template_1` (4 picks).

**Saltzpyre (`wh_`, 17 ports — `_NEEDS_ANIMS.saltzpyre` now empty):**
- `bw_dagger` → `one_handed_daggers_template_1` (10 picks); `bw_flame_sword` → `flaming_sword_template_1` (10 picks).
- `we_2h_axe` → `two_handed_axes_template_2` (9 picks); `es_dual_wield_hammer_sword` → `dual_wield_hammer_sword_template` (11 picks); `dr_dual_wield_axes` → `dual_wield_axes_template_1` (13 picks); `we_dual_wield_daggers` → `dual_wield_daggers_template_1` (12 picks); `we_dual_wield_swords` → `dual_wield_swords_template_1` (12 picks); `we_dual_wield_sword_dagger` → `dual_wield_sword_dagger_template_1` (12 picks).
- `we_spear` → `two_handed_spears_elf_template_1` (11 picks, #161 polearm re-tune); `es_halberd` → `two_handed_halberds_template_1` (9 picks, #161).
- `bw_deus_01`, `bw_necromancy_staff`, `bw_skullstaff_beam/_fireball/_flamethrower/_geiser/_spear` → the shared staff/Deus templates (4–6 picks each; `wh_` sub-key added alongside the Kruber `es_` bake).

**Notes:** The Kruber staves' `inspect_start` picks in the config were **NOT** baked — the current picker deliberately omits inspect (2026-06-29 user decision) and never applied them at runtime. `wh_hammer_book` stays in `_NEEDS_ANIMS.kruber` (no anim picks — its 3P is a mesh-swap, #181). The pre-existing stale picker `_SOURCE_MOVE_LABEL`/`_WEAPON_*` entries for already-confirmed weapons were left as-is (inert; gated out by `_PORT_STATUS.needs_anims`).

## 0.12.187-dev (2026-06-30) — Skullsplitter & Tome on Kruber: offset-free book-hide instead of a spawned mesh swap (#181)

The v0.12.186-dev spawned-unit mesh swap rendered with **crazy offsets** in-game (the freshly-spawned hammer linked to the right node with a bad transform). Replaced it with the simpler approach the user asked for: **keep the vanilla Skullsplitter hammer in its native engine position and just hide the book**, letting the `to_1h_hammer` wield redirect animate the hammer as Kruber's native 1H mace. No unit is spawned, linked, or relinked, so there are no swap-induced offsets.

- **Removed**: the force-load helper + its constant + init call, the spawn/link/`mark_for_deletion` logic, and the preview spawn-swap (no mesh is spawned anymore).
- **In-mission** (`weapon_tweaker.lua`, `_wt_hammer_book_3p_swap_apply` rewritten): on `es_` careers, when `GearUtils.spawn_inventory_unit` fires for `hand == "right"` (the book) the book 3P unit is hidden (`set_visibility`/`set_unit_visibility`, 3P-only); `hand == "left"` (the hammer) returns the vanilla units unchanged. Vanilla `show_third_person_inventory` re-shows the right-hand wielded unit on every wield (`simple_inventory_extension.lua:1017-1024`), so the book is **durably re-hidden** via the existing `show_third_person_inventory` post-hook — generalized from `_hide_brace_left_pistol` to `_rehide_hidden_3p_units` (brace → hide left pistol; `wh_hammer_book` → hide right/book; hammer kept). Still one `hook_safe` per (Class, method).
- **Inventory preview** (`_wt_hammer_book_preview_swap_apply` rewritten): drops the book's `right_hand` `spawn_data` entry so it never spawns; the hammer (`left_hand`) entry is left untouched in its native position.
- **Kept from v0.12.186-dev**: the wield patch (`one_handed_hammer_book_priest_template` es_* = `to_1h_hammer` — this IS the redirect to Kruber's 1H mace), the dev anim picker SET F entry, and the `wt_port_status` `_NEEDS_ANIMS.kruber` entry.
- **3P-only, es_-only** throughout; 1P never touched; native Warrior Priest and all non-`es_` careers unaffected.

## 0.12.186-dev (2026-06-30) — Skullsplitter & Tome on Kruber renders as a regular 1H Skullsplitter (#181)

`wh_hammer_book` ("Skullsplitter & Tome", Warrior Priest's hammer+book) on Kruber (the four `es_` careers) now renders in 3rd person as a **regular 1H Skullsplitter** — hammer in the RIGHT hand, **no book** — playing **1H mace/hammer** 3P animations. Native Warrior Priest (`wh_priest`) and all non-`es_` careers are completely unaffected. **3P-only** — 1P (universal across all six characters) is never touched.

- **Wield** (`wt_wield_patches.lua`): the four `es_*` entries for `one_handed_hammer_book_priest_template` change from `to_1h_hammer_shield` → `to_1h_hammer` (Kruber's native `es_1h_mace` / `one_handed_hammer_template_1` stance). `we_*` (Kerillian) entries unchanged.
- **3P mesh swap** (`weapon_tweaker.lua`, `_wt_hammer_book_3p_swap_apply`, dispatched from the existing `GearUtils.spawn_inventory_unit` hook): on `es_` careers, the right-hand (book) spawn is replaced with a fresh `wpn_wh_1h_hammer_01` unit linked to `Weapons.one_handed_hammer_template_1`'s right one-handed-melee node (`j_rightweaponattach`); the vanilla book is `mark_for_deletion`'d. The left-hand (original) hammer is hidden at spawn and re-hidden durably via the existing `_hide_brace_left_pistol` `show_third_person_inventory` post-hook (extended to also match `wh_hammer_book`). Husk-visibility rule mirrors the brace/longbow swaps; whole body is `pcall`-isolated with vanilla fallback. The substitute unit is force-loaded at mod init (`_force_load_hammer_book_skullsplitter_3p_unit`).
- **Inventory preview** (`_wt_hammer_book_preview_swap_apply`): same swap in the keep/hero 3P preview — right-hand `unit_name` + `unit_attachment_node_linking` rewritten to the hammer (target template's `third_person` table, so unwielded `a_unwielded_1h_right` is body-authored), left-hand entry dropped.
- **Dev anim picker** (`wt_dev_anim_picker.lua`): new Kruber SET **F = "1H Mace/Skullsplitter"** (`one_handed_hammer_template_1` vocab, which has no 1P/3P divergence), with `wh_hammer_book` added to `_WEAPON_SET`/`_WEAPON_TEMPLATE`/`_WEAPON_ATTACKS`. Surfaced for tuning via `wt_port_status` `_NEEDS_ANIMS.kruber` (`"1H Mace/Skullsplitter"`).

## 0.12.185-dev (2026-06-29) — Menu cleanup: fold Weapon Buffs in, remove Weapon Traits, move Moonfire cosmetic to Cosmetics

Three menu changes per user:
- **Weapon Buffs group removed** — its single option (Bretonnian Sword & Shield buff) moved into **Weapon Overrides** where it belongs. Orphan `wt_weapon_buffs` loc dropped.
- **Weapon Traits (Adventure) collapsible removed** — the whole group (adventure + CW melee/ranged trait toggles) and its ~84 loc entries are gone. The backing `apply_trait_filters` pool filter is neutered to a no-op (vanilla trait roll pools left untouched); cim's `wt.traits`/`wt.categories` weave-forge mapping is unaffected (separate system).
- **Moonfire Bow cosmetic AOE puff moved to cosmetics_tweaker** (Weapon & Item Appearance) — wt keeps only the gameplay `moonfire_aoe_revert`. `_wt_moonfire_on_hit` now handles revert only; the cosmetic-puff branch + `_wt_spawn_moonfire_puff` helper + `moonfire_cosmetic_puff` toggle/loc removed. See cosmetics_tweaker v0.9.48-dev.

## 0.12.184-dev (2026-06-29) — Harden localized menu labels (tests + docs) (#159/#197)

Hardening pass so the picker-localization class of bug can't silently recur. **Test:** added `dev_picker_group_labels_registered` — an END-TO-END check that asserts each picker group's **registered** loc value (`mod:localize(group_sid)`, what VMF actually renders) resolves to a real label, not a raw key or an unregistered `<key>`. This is the test that *would have caught #197* (the existing `dev_picker_names_localized` rebuilds a fresh label, so it resolved fine in-game while the registered menu labels were raw). Exposed `M.catalog_group_keys()` for it. **Docs:** new `LOCALIZATION_STANDARD.md` § 12 (dynamically-resolved menu labels: read raw loc data, never `mod:localize` during registration; no parallel hardcoded name maps) + checklist item; new `VMF_RECIPES.md` § 14 (the mod:localize-before-registration trap). No gameplay change.

## 0.12.183-dev (2026-06-29) — Fix localization-error flood + actually resolve picker names (#197)

The log flooded with `[wt][ERROR] (localize): localization file was not loaded for this mod` (27×) — introduced by v0.12.178. `_weapon_display_name` resolved documented names via `mod:localize`, but the picker catalog/labels are built at mod-init / `loc_keys()` time, **before wt's localization is registered** (the loc file dofiles the picker and calls `loc_keys()` from inside its own execution). So `mod:localize` errored per weapon AND returned nothing usable — meaning the v0.12.178 documented-names fix was also silently falling back to raw keys for the menu labels. Fixed by resolving names from wt's **raw loc table directly**: the localization file now publishes `mod._wt_loc_raw = loc` before dofiling the picker, and `_weapon_display_name` reads `mod._wt_loc_raw["unlock_<career>_<weapon>"].en` (stripping the status tag) — no `mod:localize`, no load-order dependency. So the staff names now actually resolve ("Sienna: Coruscation Staff", etc.) AND the error flood is gone. Added regression test `wt_loc_raw_published`. **Lesson:** never call `mod:localize` from a path that runs during loc registration — read the raw loc data instead.

## 0.12.182-dev (2026-06-29) — Fix Billhook (SET F) charge-attack picks not playing (#196)

Picking the Billhook's charge attacks in the dev anim picker did nothing in 3P. Cause: SET F's vocab was built from the billhook's **1P `anim_event`** names, but the picker writes the picked value as **`anim_event_3p`** — and the billhook's charge/heavy attacks have divergent 1P/3P names (1P `attack_swing_charge_stab` → 3P `attack_swing_stab_charge`, etc., confirmed in vanilla `2h_billhooks.lua`). So charge/heavy picks set a 3P event the Saltzpyre body doesn't author → fell through to idle. Rebuilt `_SALTZ_SET_VOCAB.F` from the billhook's `anim_event_3p` column (deduped). Added regression test `saltz_billhook_set_uses_3p_events`. **Class risk** (tracked in #196): the other SET vocabs were grepped the same way and may have the same latent bug wherever a target template's charge/heavy `anim_event_3p` diverges from its `anim_event` — needs a cross-set audit.

## 0.12.181-dev (2026-06-29) — Remove the inspect animation from the dev anim picker

Per user: the inspect animation should never be a tunable picker dropdown — each weapon just keeps whatever inspect animation it already uses, so there's nothing to map. Removed every `inspect_start` entry from the picker's `_WEAPON_ATTACKS` and `_SALTZ_WEAPON_ATTACKS` (the seven Sienna staves on Kruber + Saltzpyre were the only weapons that listed it). The picker no longer generates an inspect dropdown and never writes an `anim_event_3p` override for inspect. Added regression test `dev_picker_no_inspect_dropdown` so inspect can't creep back into the attack tables.

## 0.12.180-dev (2026-06-29) — +0.6 Z grip offset for the remaining Sienna staves on Kruber

Extends the Flamestorm Staff's +0.6 Z grip drop to the other six Sienna staves ported to Kruber that lacked one — **Beam, Fireball, Conflagration (geiser), Bolt (spear), Soulstealer (necromancy), and Coruscation (deus_01)** staves. They all render as Greathammer in 3P (picker SET A), so Kruber's hands need the same haft seating. Added to `_weapon_grip_offsets` (`{ es_ = {0,0,0.6} }`) and `_DURABLE_GRIP_OFFSETS` (large offset, stomped each anim tick otherwise). **`es_`-only** (Kruber) — Sienna's native `bw_*` grip is untouched; **3P + inventory-preview only**, 1P never touched.

## 0.12.179-dev (2026-06-29) — Fix Necromancer Staff soul_rip crash on cross-char wielders (FX force-load timing) (#195)

A tester crashed (`create_particles` C-fatal, `fx/wpnfx_necromancer_skullstaff_anticipation` not loaded) when firing the **Necromancy Staff's soul_rip** special on a cross-character wielder. wt *does* force-load `bw_necromancer` (which holds that FX) gated on the Necromancer DLC (`shovel`), but the gate ran only at **mod-init**, where `Managers.unlock:is_dlc_unlocked` can still be **unresolved even for an owner** — so the gate returned early (no log) and the package never loaded (confirmed in the nicho log: only `bw_unchained` force-loaded; `dlcs/shovel` was resident from boot, proving ownership). Fix: (1) ownership now also accepts the boot DLC package `dlcs/shovel` being resident (a timing-safe owner signal resolved before mod-init); (2) the force-load is idempotent and **re-attempted from `on_game_state_changed`** (keep/mission entry, ownership always resolved by then), so the package is guaranteed resident before the staff can be wielded in a mission. True non-owners still never load it (they can't wield it). Existing regression test `necromancer_fx_package_resident_if_dlc` covers residence-when-owned.

## 0.12.178-dev (2026-06-29) — Dev anim picker shows documented weapon names, not raw keys (#159)

The dev 3P Anim Picker showed **raw internal keys** for weapons missing from its hardcoded `_WEAPON_NAME` map — the tester saw "Sienna bw_deus_01" instead of "Sienna: Coruscation Staff" (all seven Sienna staves added in v0.12.157 were never added to that table, so `_weapon_display_name` fell back to the key). Fixed at the source: `_weapon_display_name` now resolves each weapon's name from the **same documented localization the Weapon Availability menu uses** (`unlock_<career>_<weapon_key>`, via a `weapon_unlock_map` lookup to a guaranteed-present career), strips the computed `[Needs Animations → …]` status tag, and only falls back to the curated map (then a source-qualified key) if no loc entry exists. The two menus can no longer diverge. Added regression test `dev_picker_names_localized` (asserts no catalog weapon's label contains its raw key) so this can't regress.

## 0.12.177-dev (2026-06-29) — Rapier on Kruber back to Empire Sword & Shield (#178)

Reverts the wrong `to_1h_sword` detour from v0.12.171: Saltzpyre's **Rapier** (`fencing_sword_template_1`) on Kruber now wields as **Empire Sword & Shield** (`to_1h_sword_shield`) again, per user — this is what was asked for originally and the bare-1H-sword redirect should never have shipped. All four `es_` careers reverted in `wt_wield_patches.lua`; `_NEEDS_ANIMS.kruber` label updated to "Empire Sword & Shield". Dev picker keeps SET C (Empire 1H Sword) for swing tuning since sword-and-shield shares the 1H-sword swing vocab (shield only adds block/bash). Kerillian (`we_`) untouched; 1P never touched.

## 0.12.176-dev (2026-06-28) — Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.12.175-dev (2026-06-28) — Hold-Pose tuner: rotation sliders actually rotate (#168 follow-up)

The rotation sliders appeared to do nothing (reported on a left-hand shield). Cause: `Quaternion.from_euler_angles_xyz` takes **degrees** (vanilla `crawl_space_extension.lua:14` passes `90` for 90°), but `_build_pose` wrapped the slider values in `math.rad()` — so a 30° input became 0.52°, ~57× too small and imperceptible. Offset (position) had no such conversion, which is why it worked. Removed the `math.rad()` wrap; degrees pass straight through. Updated the `/wt_dump_hold_pose` "Apply via" snippet to degrees so any baked rotation is correct.

## 0.12.174-dev (2026-06-28) — Bretonnian Longsword grip offset on Saltzpyre

Bake a **+0.08 Z** 3P grip offset for the **Bretonnian Longsword** (`es_bastard_sword`) when wielded by **Saltzpyre** (`wh_`-scoped). User-tuned via the hold-pose tuner. Added to `_weapon_grip_offsets` (`{ wh_ = {0,0,0.08} }`) and `_DURABLE_GRIP_OFFSETS` — durable because node 0 is reset every anim tick, so a one-shot would be stomped in-game (preview-OK/in-game-wrong). `wh_`-only (Kruber `es_` + native wielders untouched); 3P-only (1P never touched).

## 0.12.173-dev (2026-06-28) — Remove redundant Bardin 1H Axe + 1H Hammer from Saltzpyre (#187)

`dr_1h_axe` (≡ Saltzpyre's `wh_1h_axe`) and `dr_1h_hammer` (≡ Saltzpyre's `wh_1h_hammer` Skullsplitter) are redundant on Saltzpyre and are removed from the non-WP careers. Removed from the `wh_captain`/`wh_bountyhunter`/`wh_zealot` unlock_map lists + menu toggles + loc (kept for Bardin & Kerillian). Added regression test `no_redundant_bardin_1h_on_saltzpyre` so they can't creep back in (raised several times). Verified surgical via a `wh_`-specific 3-token anchor.

## 0.12.172-dev (2026-06-28) — Restore Saltzpyre Crossbow on Kruber (#138) + Cog Hammer re-tune (#182)

- **#138 Saltzpyre's Crossbow** (`wh_crossbow`) restored on Kruber. It had been dropped from the Kruber `es_` unlock_map + menu toggles even though its baked 3P anims/grip-offsets and the `a_unwielded_crossbow` crash-fix (`_patch_xchar_unwielded_attachment_safe` → `j_hips`) are intact. Re-added to all 4 `es_` unlock lists + menu toggles (default on) + loc (`"Saltzpyre: Crossbow"`). Added regression test `kruber_has_saltzpyre_crossbow` so it can't silently vanish again.
- **#182 Cog Hammer** (`dr_2h_cog_hammer`) on Kruber → moved `_CONFIRMED.kruber` → `_NEEDS_ANIMS.kruber` and re-added to the dev picker (SET A) to re-tune bad anims (same handling as #180; old `_3p_template_remaps.two_handed_cog_hammers_template_1.es_` bake left until re-tuned).

Tracking-only (open): **#183** (Kruber ranged tags/localized-names/ordering), **#184** (Kruber ranged weapons missing from dev picker), **#179** (Availability source-char ordering), **#181** (Skullsplitter & Tome model-sub).

## 0.12.171-dev (2026-06-28) — Kruber weapon status batch (#176/#177/#178/#180)

- **#176 Falchion** (`wh_1h_falchion`) + **#177 Crowbill** (`bw_1h_crowbill`) on Kruber → tagged `_CONFIRMED.kruber` (`[Working]`), user-confirmed in-game.
- **#178 Rapier** (`wh_fencing_sword`) on Kruber → wield changed `to_1h_sword_shield` → **`to_1h_sword`** (1H Sword, not sword+shield) in `wt_wield_patches.lua`; added to the dev picker (Kruber `_WEAPON_SET = "C"` Empire 1H Sword + `_WEAPON_TEMPLATE`/`_WEAPON_ATTACKS` + `_NEEDS_ANIMS.kruber`) to tune the swings, then bake.
- **#180 Saltzpyre Greathammer** (`wh_2h_hammer`) on Kruber → moved `_CONFIRMED.kruber` → `_NEEDS_ANIMS.kruber` and re-added to the picker (SET A) to re-tune the bad anims. The old career-scoped bake (`_3p_template_remaps.two_handed_hammer_priest_template.es_`) is **left in place** until re-tuned (picker picks override per-attack); clear + re-bake after the new tune.

Still open from this batch: **#179** (Weapon Availability source-character ordering), **#181** (Skullsplitter & Tome model-substitute). Dev-tool/picker + wield-patch + status only; 1P untouched.

## 0.12.170-dev (2026-06-28) — Dev Hold-Pose tuner: independent per-hand offset/rotation; remove hand dropdown (#168)

Fixes a soft-bake bug: the tuner had ONE offset/rotation slider set shared via a `wt_dev_hp_target_hand` dropdown, so setting the right hand then switching the dropdown to left reused the same values and corrupted the pose.

- **Removed** the `wt_dev_hp_target_hand` dropdown and the 6 shared sliders.
- **Added** two independent groups: **Right hand** (`wt_dev_hp_rh_offset_x/y/z`, `_rh_rot_pitch/yaw/roll`) and **Left hand** (`wt_dev_hp_lh_*`), each its own persisted offset (m) + rotation (deg).
- `_apply_pose_all()` now resolves the right and left 3P units separately and applies **each hand from its own sliders** (no shared/"both" path). Defer-to-baked guard preserved per hand (all-zero = no write). `/wt_dev_hp_reset` zeros all 12; the dump emits both hands. 3P-only; `_resolve_wielded` + 1P untouched.

## 0.12.169-dev (2026-06-28) — Saltzpyre dev picker batch 3: polearm regression (Kerillian Spear + Kruber Halberd) (#161)

Adds **Kerillian's Spear** (`we_spear`, `two_handed_spears_elf_template_1`) and **Kruber's Halberd** (`es_halberd`, `two_handed_halberds_template_1`) to the Saltzpyre dev anim picker so the regressed swings can be re-tuned. New picker **SET F = Saltzpyre Billhook** (`two_handed_billhooks` vocab, grepped). Both moved from `_CONFIRMED.saltzpyre` → `_NEEDS_ANIMS.saltzpyre`.

- Diagnosis: the **wield is already correct** (`two_handed_spears_elf_template_1` + `two_handed_halberds_template_1` both `wh_* = "to_2h_billhook"`, the Saltzpyre Billhook stance — `2h_billhooks.lua:1468`). The regression is the classic polearm class (CHANGELOG **v0.12.64-dev**): the stance renders but per-attack **swing events no-op** on the billhook SM unless remapped. Re-tune the swings in the picker (SET F), then bake; root-cause of the swing-remap drop tracked in **#161**.
- Localized-name dev comments added next to the internal keys (Kerillian "Spear" / Kruber "Halberd" / Saltzpyre "Bill Hook") per the new localization convention (#159).

## 0.12.168-dev (2026-06-28) — FIX (render lever): Saltzpyre dual axes → axe&falchion, dagger → falchion via WIELD PATCH

Corrects a mistake from .164/.165: re-pointing the dev picker SET only changes the dev tool's dropdown options — it does **not** change the rendered animation. The actual lever is `wt_wield_patches.lua` (`wield_anim_career_3p`). Both weapons were still rendering the old anims:
- **Bardin Dual Axes** (`dual_wield_axes_template_1`) on Saltzpyre was `wh_* = "to_dual_hammers_priest"` (WP Dual Hammers) → now **`to_dual_axe_sword_wh`** (Dual Axe & Falchion), as requested.
- **Sienna Dagger** (`one_handed_daggers_template_1`) on Saltzpyre was `wh_* = "to_fencing_sword"` (Rapier) → now **`to_1h_sword`** (1H Falchion's wield; `1h_falchions.lua:1183`).

(`es_dual_wield_hammer_sword` was already `to_dual_axe_sword_wh`, so it was correct.) Added regression tests `saltzpyre_dual_axes_wield_axe_falchion` + `saltzpyre_dagger_wield_falchion` asserting the wield values. Picker SETs/`_NEEDS_ANIMS` already aligned in .164/.165 for per-attack tuning on top.

## 0.12.167-dev (2026-06-28) — Regression markers for this session's crash fixes + dual-hammers removal

Added three `/wt_regression_test` checks so the session's fixes can't silently regress:
- **`fire_fx_package_resident`** (#128) — asserts `careers/bw_unchained` is force-loaded (drakefire/fireball/flamethrower AOE particles resident for cross-character wielders).
- **`necromancer_fx_package_resident_if_dlc`** (v0.12.163) — asserts `careers/bw_necromancer` is resident when the Necromancer (`shovel`) DLC is owned (Soulstealer/Necromancy staff soul_rip particle); SKIPs when the DLC isn't owned (the load is intentionally DLC-gated).
- **`no_dwarf_dual_hammers_on_saltzpyre`** (v0.12.164) — asserts `dr_dual_wield_hammers` stays out of the `wh_captain`/`wh_bountyhunter`/`wh_zealot` unlock lists (redundant with Dual Skullsplitters).

The two package checks are **runtime residence assertions** (`Managers.package:has_loaded`), run in-keep via `/wt_regression_test`. No behavior change.

## 0.12.166-dev (2026-06-28) — Saltzpyre: Empire Hammer & Sword → Dual Axe & Falchion anims

`es_dual_wield_hammer_sword` (Empire Mace & Sword) on Saltzpyre now redirects to **Dual Axe & Falchion** (picker SET C) instead of WP Dual Hammers (SET B). Updated `_SALTZ_WEAPON_SET` + `_NEEDS_ANIMS.saltzpyre`. With this, all Saltzpyre dual-wields (Kerillian daggers/swords/sword-dagger, Bardin dual axes, Empire hammer&sword) share SET C; **SET B (WP Dual Hammers) now has no assigned weapon** (left defined). Picker-only; tune then bake. Kruber unchanged.

## 0.12.165-dev (2026-06-28) — Saltzpyre: Sienna Dagger → 1H Falchion anims (was Fencing Sword)

`bw_dagger` (Sienna Dagger) on Saltzpyre now redirects to **1H Falchion** (picker SET E) instead of Fencing Sword/Rapier (SET D). Updated `_SALTZ_WEAPON_SET` + `_NEEDS_ANIMS.saltzpyre` display. SET D (Fencing Sword) now has no assigned weapon — left defined for possible future reuse. Picker-only; tune per-attack then bake. Kruber's dagger (separately baked → Empire 1H Sword) is untouched.

## 0.12.164-dev (2026-06-28) — Saltzpyre: dual axes → Dual Axe & Falchion; drop redundant Dwarf Dual Hammers

Two Saltzpyre cross-character tweaks (user-directed):
1. **Bardin Dual Axes (`dr_dual_wield_axes`) now redirects to Dual Axe & Falchion** (picker SET C) instead of Warrior Priest Dual Hammers (SET B) — an axe-containing dual-wield → axe-containing dual-wield is the better visual fit. Picker `_SALTZ_WEAPON_SET` + `_NEEDS_ANIMS.saltzpyre` display updated; tune per-attack in the dev picker, then bake.
2. **Removed Dwarf Dual Hammers (`dr_dual_wield_hammers`) from Saltzpyre entirely** — redundant with the **Dual Skullsplitters** (`wh_dual_hammer`) the non-WP Saltzpyre careers already have. Removed from the unlock map (`wh_captain`/`wh_bountyhunter`/`wh_zealot` only — Bardin & Kerillian keep it), the dev picker tables (`_SALTZ_WEAPON_SET`/`_TEMPLATE`/`_ATTACKS`), `_NEEDS_ANIMS.saltzpyre`, and the menu toggles + loc keys for those 3 careers.

Data-only / picker-only; no apply-path or core-logic change. Kruber unchanged.

## 0.12.163-dev (2026-06-28) — FIX: Necromancy/Soulstealer Staff CTD on cross-character wielders (DLC-gated package)

Fixes a second cross-character particle crash (same class as #128, different package). Firing the **Necromancy / Soulstealer Staff** (`bw_necromancy_staff`, `staff_death`) `soul_rip` attack on a non-Necromancer wielder CTD'd the host (nicho, 2026-06-28):

```
create_particles failed, Particle effect '#ID[418bb6de77c32555]' not loaded
effect_name = "fx/wpnfx_necromancer_skullstaff_anticipation"  | sub_action = "soul_rip"
```

**Root cause.** The #128 fix force-loads `careers/bw_unchained`, which covers every Sienna staff a base Sienna career can wield (beam/fireball/geiser/spark-spear/flamethrower/coruscation). But the Necromancy Staff is **Necromancer-exclusive**, so its particles live only in the `bw_necromancer` career package (verified: bundle `82250c065e5b8ade` contains `418bb6de77c32555`) — not in bw_unchained.

**Fix.** Also force-load `resource_packages/careers/bw_necromancer` at mod init. Because it's a **DLC career (`shovel`)**, the load is **gated on DLC ownership** (`Managers.unlock:is_dlc_unlocked("shovel")`, with `dlc_exists` pre-check) — force-loading a DLC package a non-owner doesn't have installed would itself async-crash. Only owners can wield the Necromancy Staff, so non-owners need nothing. With this, `bw_unchained` (non-DLC, all base-Sienna staves) + `bw_necromancer` (DLC, the Necromancy Staff) cover every cross-character Sienna staff.

- 3P/particle-residence only; no apply-path change. Not yet in-game verified — needs the soul_rip retest on a cross-character Necromancy Staff.

## 0.12.162-dev (2026-06-27) — Bake Flamestorm Staff grip offset (+0.6 Z) on Kruber

User-tuned grip offset baked for the Sienna **Flamestorm Staff** (`bw_skullstaff_flamethrower`) when wielded by Kruber: `_weapon_grip_offsets.bw_skullstaff_flamethrower.es_ = {0, 0, 0.6}`, added to `_DURABLE_GRIP_OFFSETS` (per-frame re-apply, same path as the scythe/glaive) so the engine's per-tick canonical-pose reset can't stomp it. Seats Kruber's hands on the staff haft (the staff renders as Greathammer in 3P via the staff anim redirect).

- **es_ ONLY (Kruber)** — Sienna's native `bw_*` careers find no prefix match → offset stays nil → native Sienna grip untouched. **3P-ONLY** by construction (`_offset_weapon_units` + durable re-apply write only `*_unit_3p`, never 1P — `feedback_cross_char_transforms_3p_only`). Single source of truth = `_weapon_grip_offsets`; `_DURABLE_GRIP_OFFSETS` is just the membership set.
- No new hook, no apply-path change. Mirrors the scythe (`+0.6 Z`) and glaive (`+0.285 Z`) durable offsets.

## 0.12.161-dev (2026-06-27) — Saltzpyre dev picker batch 2: 7 Sienna staves

Adds the 7 Sienna staves (Beam / Fireball / Flamethrower / Geiser / Spark-Spear / Necromancy / Coruscation) to the Saltzpyre side of the dev 3P Anim Picker, mapped to **SET A (Warrior Priest Greathammer, 2-handed grip)** — mirroring how the same staves were handled for Kruber (staves → Greathammer). The staff cast/charge source events get one dropdown each, options = the WP Greathammer 2H swing vocab; tune per-cast in-game, then bake career-scoped (`wh_`).

- Source attack data for all 7 staves is reused verbatim from the verified Kruber `.157` staff `_WEAPON_ATTACKS` (source events are receiver-independent). Templates re-confirmed. All 7 verified present in the `wh_captain`/`wh_bountyhunter`/`wh_zealot` unlock lists (equippable on Saltzpyre).
- `_NEEDS_ANIMS.saltzpyre` gains the 7 staves (redirect-target display "Warrior Priest Greathammer"); `_SALTZ_WEAPON_SET/_TEMPLATE/_ATTACKS` gain the 7 entries. Saltzpyre picker now lists 16 ports (9 melee batch-1 + 7 staves).
- Dev-tool only, 3P-only — no apply-path/bake/ship change. Kruber unchanged. CAVEAT: SET A target is a Warrior Priest weapon (`bless` DLC); staff anims fall through to idle without the DLC (no crash). Remaining Saltzpyre batches: shields (7), ranged (pistols/crossbow/drakegun), throwing axes/javelin.

## 0.12.160-dev (2026-06-27) — Dev 3P Anim Picker now multi-receiver; added Saltzpyre batch 1

The dev-only 3P Anim Picker (`wt_dev_anim_picker.lua`) is refactored from KRUBER-only to **multi-receiver** via a `_RECV` dispatch table, and seeded with the first Saltzpyre batch. Dev-tool only, 3P-only — no change to the apply path or to any baked/shipped animation.

### What changed
- **New `_RECV` dispatch** keyed by receiver (`kruber` / `saltzpyre`). The existing Kruber data tables (`_SET_LABEL` / `_SET_VOCAB` / `_SET_MOVE_LABEL` / `_WEAPON_SET` / `_WEAPON_TEMPLATE` / `_WEAPON_ATTACKS` / `_SOURCE_MOVE_LABEL`) are **left byte-identical**; Kruber simply points at them through `_RECV.kruber`. The catalog builder, vocab/label readers, `loc_keys`, dump and coverage headers were repointed at `_RECV`.
- **Kruber output unchanged** — same `p_kruber_*` port_ids, same setting_ids, same labels. Saltzpyre adds 9 new `p_saltzpyre_*` entries.
- **Saltzpyre batch 1 = 9 melee cross-character ports across 5 SETs:** WP Greathammer (A), WP Dual Hammers (B), Dual Axe & Falchion (C), Fencing Sword / Rapier (D), 1H Falchion (E). Surfaced via the new `_NEEDS_ANIMS.saltzpyre` allow-list in `wt_port_status.lua` (rendered on the non-WP Saltzpyre body: wh_captain / wh_bountyhunter / wh_zealot).
- Weapons: Kerillian Glaive (`we_2h_axe` → A); Kruber Mace & Sword (`es_dual_wield_hammer_sword`), Bardin Dual Axes (`dr_dual_wield_axes`), Bardin Dual Hammers (`dr_dual_wield_hammers`) → B; Kerillian Dual Daggers / Dual Swords / Sword & Dagger (`we_dual_wield_*`) → C; Sienna Dagger (`bw_dagger` → D); Sienna Flaming Sword (`bw_flame_sword` → E).

### Caveats
- **WP-DLC dependency on SET A/B:** the SET A (WP Greathammer) and SET B (WP Dual Hammers) redirect targets are Warrior-Priest weapons (`bless` DLC). Their anims live on the shared Saltzpyre body but may be absent without the DLC — the picker falls through to the idle stance (no T-pose, no crash).
- **Move labels are raw-event for batch 1** — Saltzpyre's `set_move_label` / `source_move_label` maps are intentionally empty, so rows/options show the raw `anim_event` (the resolvers already fall back to the raw event). Polished move labels are a follow-up.

## 0.12.159-dev (2026-06-27) -- FIX: cross-character fire/explosion weapons CTD non-native careers

Fixes a hard crash-to-desktop reported by nicho (host, 2026-06-25): equipping a Bardin/Sienna **fire weapon** on a career that doesn't natively own it (e.g. **Drakefire Pistols on Foot Knight**) and firing it crashed the game on the AOE detonation —

```
<<Lua Error>> WorldApi create_particles failed, Particle effect '#ID[35874310a062bfd8]' not loaded
Assertion failed `...resource_manager().can_get(particle_type, particle_name)` at c_api_world.cpp:384
  DamageUtils.create_explosion -> World.create_particles
```

**Root cause.** The drakefire/fireball AOE explosion particle `fx/wpnfx_drake_pistols_projectile_impact` (murmur64A `35874310a062bfd8`) is referenced by *string* in `ExplosionTemplates`, so it is not a build-time dependency of the weapon's unit bundle. It is bundled into the **career packages** of the careers that natively wield these weapons (Bardin `dr_*`, Sienna `bw_*`). A cross-character wielder loads the weapon unit but never that career package → the resource manager can't get the particle at detonation → C-level assert (bypasses `pcall`, same class as the existing brace/crossbow unit force-loads).

**Fix.** Force-load one vanilla, non-DLC Sienna career package (`resource_packages/careers/bw_unchained`) at mod init, mirroring the existing `_force_load_brace_repeater_3p_unit` pattern. Verified via `vt2_bundle_unpacker` that this single ~10 MB package contains **all** the common cross-character fire particles at once — `wpnfx_drake_pistols_projectile_impact` (Drake Pistols AOE + Fireball basic), `wpnfx_fireball_charged_impact_remap` + `wpnfx_fireball_charged_impact` (Fireball charged), and `wpnfx_flamethrower_01` (Drakegun + Flamethrower staff) — so the one load covers Drake Pistols, Drakegun, and the fireball/flamethrower staves for every wt user. Vanilla package = Steam-verified complete bundle, so the force-load is safe (no missing-member C-fatal); this is resource-pool memory, not the Lua heap.

- **Not yet in-game verified** — needs a non-Bardin career (Foot Knight) to equip Drakefire Pistols via wt, fire a charged shot, and confirm no crash on detonation. The `[wt fire-fx]` printf logs the force-load result at boot.
- **Follow-up:** the Sienna flaming-flail particle (`0df4b41f`) lives in the `anvil` DLC package (DLC-gated, lower-traffic cross-char port) and is deferred to a later batch.

## 0.12.158-dev (2026-06-27) -- Bretonnian Sword and Shield damage buff toggle (live, no restart)

New opt-in toggle `wt_brett_sword_shield_buff` (Weapon Buffs group, default OFF). Buffs ONLY the Bretonnian Sword and Shield (template `one_handed_sword_shield_template_2`, used only by that weapon and its skins, so nothing leaks to other weapons).

- All attacks: +10% damage (`power_distribution.attack`), +10% attack speed (`anim_time_scale`), headshot coefficient set to 2, vs-monster (`armor_modifier.attack[3]`) set to 4, vs-berserker (`armor_modifier.attack[5]`) set to 1.25. On top: `heavy_attack_stab` (heavy 3) +20% damage, `light_attack_right` (light 2) +10% faster, `light_attack_stab_postpush` (push follow-up) +20% damage. The push action itself is untouched.
- Scoped via private `wt_brettsns_` damage-profile and PowerLevelTemplates clones (mirrors character_weapon_variants `_clone_damage_profile` and its anim_time_scale loop). Applies and reverts LIVE via `mod.wt_apply_brett_buff` (`on_setting_changed` plus once at load), no restart: captures vanilla values once, then swaps the template's per-attack fields between vanilla and buffed.
- `[wt:brettsns]` printf logs each attack's current headshot/monster/berserker for verification (expected 1.5 / 0.75 / 2.5). Armor indices verified from breeds (rat_ogre and chaos_troll armor_category 3 = monster; chaos_berzerker and skaven_plague_monk 5 = berserker). NOT in-game tested; multiplayer note: all peers should run the same wt build for consistent networked damage.

## 0.12.156-dev (2026-06-25) — BAKE the final 7 Kruber [Needs Animations] 3P ports (picker now empty)

The last seven cross-character ports flagged `[Needs Animations]` on Kruber are now baked as permanent **career-scoped defaults** in `_3p_template_remaps` (`weapon_tweaker.lua`), so they render correctly for every subscriber **with no dev picker, no setting, and no per-user configuration**. The picks were pulled verbatim from the user's persisted dev anim picker (`user_settings.config`, 2026-06-25). With these baked, **`_NEEDS_ANIMS.kruber` is now empty** — every Kruber picker port is baked.

### What changed
- **Baked into `_3p_template_remaps`** (`weapon_tweaker.lua`), each entry career-scoped (native owner's prefix `= false` so its 3P plays UNTOUCHED; `es_` carries the Kruber-only redirect):
  - `we_one_hand_axe_template` — Kerillian 1H Axe (`we_1h_axe`) → Kruber native 1H Axe (`to_1h_axe`, mostly identity).
  - `two_handed_axes_template_2` — Kerillian Glaive (`we_2h_axe`) → Empire Greathammer (durable +0.285 Z grip offset already set v0.12.152).
  - `dual_wield_daggers_template_1` — Kerillian Dual Daggers (`we_dual_wield_daggers`) → Empire Mace & Sword.
  - `dual_wield_sword_dagger_template_1` — Kerillian Sword & Dagger (`we_dual_wield_sword_dagger`) → Empire Mace & Sword.
  - `dual_wield_swords_template_1` — Kerillian Dual Swords (`we_dual_wield_swords`) → Empire Mace & Sword.
  - `dual_wield_hammers_priest_template` — WP/Saltzpyre Dual Skullsplitters (`wh_dual_hammer`) → Empire Mace & Sword (`wh_ = false` covers both Saltzpyre and Warrior Priest).
  - `one_handed_flail_shield_template` — WP/Saltzpyre Flail & Shield (`wh_flail_shield`) → Empire Mace & Shield.
  Each `es_` table maps the template's fired source `anim_event` → the user's picked target, verbatim from the config. Consumed at the `Unit.animation_event` hook via `state.remap` — **3P body only**. Identity entries are harmless re-fires; `__unset__` picks were omitted (fall through to native). No new apply call, no new hook.
- **Picker removal** (`wt_port_status.lua`): all 7 keys deleted from `_NEEDS_ANIMS.kruber` (now `{}`) and added to `_CONFIRMED.kruber` so the dev picker drops them and the Weapon Availability tag reads `[Working]`. The stale `we_2h_axe` grip-offset note updated to reflect the anim is now baked too.

### Scope / safety
**3P-ONLY** — no `anim_event`/`wield_anim`/`state_machine`/1P-unit read or write; anim redirects on the 3P-body hook path only. Native owners (Kerillian / Saltzpyre / Warrior Priest) play untouched via the owner-prefix `false` fall-through. No new file-scope locals at chunk scope; 200-locals respected. Docs updated: `ANIMATION_COVERAGE.md` (5 rows / 7 keys → ✅ BAKED `[Working]`; stale chooser-exclusion-sync note removed).

## 0.12.155-dev (2026-06-25) — Ship baked Kruber 3P picks + correct scythe grip (+6 → +0.6), dev override defers to bake

Release roll-up of the baked Kruber 3P animation-picker work (v0.12.149/.150/.151-dev) to the **public** `weapon_tweaker` Workshop item (id 3712896117). The finished Kruber 3P picks for the cross-character ports — **Bardin's Pickaxe, Bardin's Dual Axes, Sienna's Fire Sword, Sienna's Dagger, Sienna's Mace, the Necromancer Ghost Scythe, the Warrior Priest / Saltzpyre Greathammer, and the Outcast Engineer Coghammer** — are baked into `_3p_template_remaps` as permanent **career-scoped defaults**, so they render correctly for every subscriber **with no dev picker, no setting, and no per-user configuration required**. The picks were captured verbatim from the user's `[wt:play]` log.

### What ships in this build
- **Baked picks live in `_3p_template_remaps`** (`weapon_tweaker.lua`), each entry career-scoped: the native owner's career prefix is `false` (so `_resolve_template_remap` returns nil → the native owner's 3P plays UNTOUCHED), and the `es_` (Kruber) branch carries the redirect. Consumed at the `Unit.animation_event` hook via `state.remap` — **3P body only** (the 1P hands unit is excluded upstream; 1P is never touched per the universal-1P rule). No new apply call, no new hook (VMF duplicate-hook rule respected).
- **Scythe 3P grip offset corrected `+6` → `+0.6` Z** in `_weapon_grip_offsets` (`bw_ghost_scythe.es_ = {0, 0, 0.6}`). The prior `+6` value was a 10× metres overshoot (the offset is in metres, so `6` flung the haft 6 m off-body); the corrected `0.6` seats Kruber's hands on the scythe haft. Career-scoped to Kruber's `es_*` and applied via the durable per-frame re-apply path (`_DURABLE_GRIP_OFFSETS`) so the engine's per-tick canonical-pose reset can't stomp it. 3P-only by construction (`_offset_weapon_units` `unit_fields` is hardcoded to `*_3p`); Sienna's native scythe grip is provably not moved (no `bw_*` prefix match).
- **Dev grip-offset override now defers to the baked value at its `0` default.** The Hold-Pose Tuner's `wt_dev_hp_live_apply` checkbox defaults to `false` (live per-frame apply OFF) and the dev offset sliders default to `0`, so a stock install never touches the wielded weapon unit — the baked `_weapon_grip_offsets` / durable re-apply value survives untouched for every subscriber. Belt-and-suspenders: `_apply_pose_to` also no-ops when all sliders are `0`, so even with live-apply on, an untouched tool can't clobber the bake. The user enables the override deliberately only when tuning a new weapon.
- **No new logic in this version** beyond the grip-offset correction + version bump — this entry also ships the already-baked .149/.150/.151 remap data to the public item as a clean release. The dev picker / `[wt:apply]`/`[wt:play]` instrumentation is retained for the remaining flagged weapons.

### Scope / safety
**3P-ONLY** — no `anim_event`/`wield_anim`/`state_machine`/1P read or write; native owners (Bardin / Sienna / Saltzpyre-WP) play untouched via the owner-prefix `false` fall-through. The grip-offset correction is a single data-value edit (`6` → `0.6`) on an already-es_-scoped entry — no new prefix match, no native-wielder exposure. No new file-scope locals at chunk scope; 200-locals cap respected.

## 0.12.154-dev (2026-06-24) — Strip dev-only `[confirmed working]` tags from the public labels

Follow-up to v0.12.153-dev (which stripped `[untested]`). Stripped the leading `[confirmed working] ` display prefix from **19** user-facing `en = "..."` label values in `weapon_tweaker_localization.lua` (cross-character weapon-unlock rows: Kerillian Spear, Saltzpyre Axe/Billhook across Mercenary/Huntsman/Knight/Questing Knight + the Waywatcher/Maidenguard/Shade/Thornsister axe rows + the Captain/Bounty Hunter/Zealot spear rows). Display-string-only edit — no logic, hooks, or behavior changed. Verified 0 `[confirmed working]` occurrences remain in any `en =` value. The legitimate feature/category tags `[CW]` (Chaos Wastes) and `[Big Rebalance]` were left intact (21 occurrences unchanged).

## 0.12.153-dev (2026-06-24) — Strip dev-only `[untested]` tags from the public labels

This is the **public** `weapon_tweaker` Workshop item (id 3712896117, visibility=public). The dev-only `[untested]` prefix tags were leaking onto the live in-game labels.

### What changed
- **`weapon_tweaker_localization.lua`** — stripped the leading `[untested] ` display prefix from **629** user-facing `en = "..."` label values (cross-character weapon-unlock rows: `unlock_es_mercenary_*`, etc.). The labels now read clean (e.g. `"Bardin: Great Axe"` instead of `"[untested] Bardin: Great Axe"`). Verified: **0** `[untested]` occurrences remain in any `en =` value. The 4 remaining `[untested]` mentions in this file are code comments / status-vocabulary docs (non-display) and were left untouched.
- **`wt_port_status.lua`** — untouched; its `[Untested]` occurrences are status-tracking literals and comments, not user-facing loc strings.

### Scope / safety
Display-string-only edit — no logic, hooks, or behavior changed. The `*_dev` weapon_tweaker item keeps its tags (dev surface).

## 0.12.150-dev (2026-06-24) — BAKE Sienna's Mace + Necromancer Scythe as PERMANENT Kruber-only 3P defaults (+ Scythe 3P grip offset)

Two more weapons the user finished tuning on Kruber — **Sienna's Mace (`bw_1h_mace`)** and the **Necromancer Ghost Scythe (`bw_ghost_scythe`)** — are now baked as permanent career-scoped defaults so they ship without the dev picker. The picks were captured verbatim from the user's `[wt:play]` log. Both render as **Empire Greathammer** in 3P on Kruber; the Scythe additionally gets a **+0.569 Z 3P grip offset** (Kruber-only) so Kruber's hands sit on the haft. Mirrors the v0.12.149-dev 4-weapon bake exactly, plus the one extra offset step.

### What changed
- **Baked into `_3p_template_remaps`** (`weapon_tweaker.lua`), career-scoped:
  - `one_handed_hammer_wizard_template_1` — `bw_ = false` (Sienna native untouched), `es_ = {…}` (Kruber → Empire Greathammer). 13 source→target picks.
  - `staff_scythe` — `bw_ = false` (Sienna native untouched), `es_ = {…}` (Kruber → Empire Greathammer). 15 source→target picks; the two scythe specials (`special_action` / `special_action_02`) have no SET A twin and are mapped to the nearest Greathammer events per the user's picks (`attack_swing_charge` / `attack_swing_down_left`).
  Each `es_` table maps the template's fired source `anim_event` → the user's picked target, verbatim from the dump. Resolved via the existing `_resolve_template_remap` (prefix-matched, `weapon_tweaker.lua:1078`) and consumed at the `Unit.animation_event` hook via `state.remap` (`weapon_tweaker.lua:1510`) — **3P body only** (the 1P hands unit is excluded upstream). The native owner's `bw_ = false` makes `_resolve_template_remap` return nil for any Sienna (`bw_*`) career → native plays untouched (same precedent as `flaming_sword_template_1.bw_ = false`). No new apply call, no new hook (VMF duplicate-hook rule respected — none added).
- **Scythe 3P grip offset BAKED** into `_weapon_grip_offsets` (`weapon_tweaker.lua`): `bw_ghost_scythe = { es_ = {0, 0, 0.569} }`. **Career-scoped to `es_` only** — `_offset_weapon_units` matches by career prefix (`career_name:sub(1, #prefix) == prefix`, `weapon_tweaker.lua:1972`), so only Kruber's `es_*` careers match; Sienna's `bw_*` careers find no matching prefix → `offset` stays nil → early return → **Sienna's native scythe grip is NOT moved**. **3P-ONLY by construction** — `_offset_weapon_units`' `unit_fields` list is hardcoded to `{ "left_unit_3p", "right_unit_3p" }` (the `*_1p` fields were removed as a latent bug in v0.12.136); it CANNOT touch 1P. Applied at both rendering paths via the shared helper (in-game `GearUtils.create_equipment` + menu `MenuWorldPreviewer._spawn_item_unit`). Per the table's own NOTE, this one-shot `create_equipment` write CAN be stomped by the engine's per-frame attachment re-apply on some weapons — if the Scythe snaps back in testing, escalate to a **career-gated `unit_attachment_node_linking.third_person` mutation** (NOT a raw `staff_scythe` linking write — that surface is shared with Sienna).
- **Picker removal** (`wt_port_status.lua`): `bw_1h_mace` and `bw_ghost_scythe` deleted from `_NEEDS_ANIMS.kruber` (the catalog/setting-index gate) so the dev picker no longer surfaces them; both added to `_CONFIRMED.kruber` so the Weapon Availability tag reads `[Working]`. `bw_ghost_scythe` ALSO removed from `_NEEDS_OFFSETS.kruber` (now `{}`) since its offset is applied, not pending — so `M.tag` stops returning `[Needs Offsets]`. Mirrored out of the picker's `_WEAPON_SET` for lockstep.
- **Picker retained for the REMAINING flagged weapons** (Coghammer, WP Greathammer, WH 1H Axe, the Kerillian dual/2H ports, etc.); the `[wt:apply]`/`[wt:play]` instrumentation is kept to capture future picks.

### Scope / safety
**3P-ONLY** — no `anim_event`/`wield_anim`/`state_machine`/1P-unit read or write; anim redirects on the 3P-body hook path only, grip offset via `_offset_weapon_units` whose `unit_fields` is hardcoded to `*_3p`. Native Sienna 3P + grip is provably untouched (owner prefix `bw_ = false` for anims; `es_`-prefix-only match for the offset; the two new templates had no prior `_3p_template_remaps` entry, so the native-owner fall-through chain is byte-identical to pre-bake). No new file-scope locals at chunk scope; 200-locals respected. Docs updated: `ANIMATION_COVERAGE.md` (2 rows → ✅ BAKED `[Working]`), `KRUBER_3P_ANIM_DECISIONS.md` (BAKED table + provenance picks + status rows; Scythe offset noted).

## 0.12.149-dev (2026-06-24) — BAKE 4 finished Kruber 3P picks as PERMANENT, CAREER-SCOPED defaults (3P-ONLY)

The four weapons the user finished tuning on Kruber — **Bardin's Pickaxe, Bardin's Dual Axes, Sienna's Fire Sword, Sienna's Dagger** — are now baked as permanent defaults so they ship to every friend and subscriber WITHOUT the dev picker. The picks were captured verbatim from the user's `[wt:play]` log.

### Why a career-scoped remap, NOT a shared `anim_event_3p` write
All four templates carry **no authored `anim_event_3p` natively** (verified against the decompiled `2h_picks.lua`, `dual_wield_axes.lua`, `1h_swords_flaming_spell.lua`, `1h_dagger_wizard.lua` — `anim_event` only). So `weapon_unit_extension.lua:512` (`anim_event_3p or event`) fires the source `anim_event` string on **every wielder's own 3P body** at `:652`. Writing the shared template's `anim_event_3p` (what the dev picker's raw apply does) would make the **NATIVE owners** — Bardin (pickaxe, dual axes) and Sienna (fire sword, dagger) — fire the Kruber-tuned string on THEIR skeletons too, silently breaking the native 3P view for any non-Kruber wielder. The bake avoids this entirely.

### What changed
- **Baked into `_3p_template_remaps`** (`weapon_tweaker.lua`), career-scoped:
  - `two_handed_picks_template_1` — `dr_ = false` (Bardin native untouched), `es_ = {…}` (Kruber → Empire Greathammer).
  - `flaming_sword_template_1` — `bw_ = false` (Sienna native untouched), `es_ = {…}` (Kruber → Empire 1H Sword).
  - `one_handed_daggers_template_1` — `bw_ = false`, `es_ = {…}` (Kruber → Empire 1H Sword).
  - `dual_wield_axes_template_1` — ADDED `es_ = {…}` to the existing entry (Kruber → Empire Mace & Sword); the `dr_ironbreaker`/`dr_ranger`/`dr_engineer` Bardin-cross block and the implicit `dr_slayer`-native fall-through are unchanged.
  Each `es_` table maps the template's fired source `anim_event` → the user's picked target, verbatim from the dump. Resolved via the existing `_resolve_template_remap` (prefix-matched) and consumed at the `Unit.animation_event` hook — **3P body only** (the 1P hands unit is excluded upstream). The native owner's `dr_`/`bw_` = `false` makes `_resolve_template_remap` return nil → native plays untouched (same precedent as `two_handed_billhooks_template`'s `wh_ = false`). No new apply call, no new hook (VMF duplicate-hook rule respected — none added).
- **Picker removal** (`wt_port_status.lua`): the 4 weapon_keys (`dr_2h_pick`, `dr_dual_wield_axes`, `bw_dagger`, `bw_flame_sword`) deleted from `_NEEDS_ANIMS.kruber` (the catalog/setting-index gate) so the dev picker no longer surfaces them. Their now-inert stored VMF settings can't fight the bake — the apply path iterates only `_setting_index`, which is gated on the catalog, which is gated on `_NEEDS_ANIMS`. Same keys added to `_CONFIRMED.kruber` so the Weapon Availability tag reads `[Working]`. Mirrored out of the picker's `_WEAPON_SET` for lockstep.
- **Picker retained for the REMAINING flagged weapons** (Coghammer, WP Greathammer, WH 1H Axe, the Kerillian dual/2H ports, scythe, etc.); the `[wt:apply]`/`[wt:play]` instrumentation is kept to capture future picks.

### Scope / safety
**3P-ONLY** — no `anim_event`/`wield_anim`/`state_machine`/1P-unit read or write; only `anim_event_3p`-equivalent redirects on the 3P-body hook path. Native Bardin/Sienna 3P is provably untouched (owner prefix `false`; the three new templates had no prior `_3p_template_remaps` entry, so the native-owner fall-through chain is byte-identical to pre-bake). No new file-scope locals at chunk scope (the dual-axes `es_t` lives inside the existing IIFE closure); 200-locals respected. Docs updated: `ANIMATION_COVERAGE.md` (4 rows → ✅ BAKED), `KRUBER_3P_ANIM_DECISIONS.md` (Completed Picks → BAKED section + status rows).

## 0.12.148-dev (2026-06-24) — 3P Anim Picker: gameplay MOVE LABELS on rows + dropdown options (3P-ONLY, display-only)

The dev 3P Anim Picker now shows gameplay move labels (Light 1 / Heavy 2 / Charge N (windup) / Push / Push Attack / Block) move-first on every attack ROW and every dropdown OPTION, with the raw `anim_event` kept as a secondary clarifier so each entry stays unambiguous. Previously every row and option rendered the bare engine event name (`attack_swing_down_left`), which told the user nothing about which actual swing it drives.

### What changed
Two new static label maps mirroring the existing vocab/attack structure, with no behavioral change to the apply path:
- `_SET_MOVE_LABEL[set][anim_event]` — the TARGET-set move label per dropdown OPTION (e.g. SET A `attack_swing_heavy` → "Heavy 2"). Mirrors `_SET_VOCAB` 1:1; all 55 vocab options (5 sets × 11) labeled.
- `_SOURCE_MOVE_LABEL[weapon_key][anim_event]` — the SOURCE-weapon move label per attack ROW (e.g. `dr_2h_pick` `attack_swing_down_left` → "Heavy 1"). Mirrors `_WEAPON_ATTACKS` 1:1.

Both resolved offline by chain-tracing the decompiled weapon templates (the authoritative sub-action NAME is the light/heavy classifier — `light_attack_*` = Light, `heavy_attack_*` = Heavy; the `kind="melee_start"` charge poses = "Charge N (windup)"). All five sets are charge-style templates: `action_one` opens on a held charge windup that branches to a light or heavy swing on release; `attack_push` = Push; `parry_pose` = Block.

### Label format
- Attack ROW label: `↳ Light 1  ·  attack_swing_down_left` (move-first, U+00B7 middle-dot separator, raw event as clarifier).
- Dropdown OPTION label: `Heavy 2  ·  attack_swing_heavy`. The stored setting `value` is STILL the raw `anim_event` verbatim — only the displayed `text` is the move-first label, so the apply path (`mod:get(sid)` → `_apply_anim_event_change`) is untouched. Two new helpers `_move_label_for_set` / `_move_label_for_source` build the strings; `_build_options` and `loc_keys` register each label string as its own VMF loc key (raw forms also registered for fall-through).

### Raw-event fallbacks (no clean move label — 4 of 186 source attacks)
Where a source attack has no clean target-set twin, the label falls back to the raw event name (never blank): `bw_ghost_scythe` `special_action` / `special_action_02` (Necromancer scythe special), `bw_flame_sword` `attack_swing_right_spell` (spell attack), `wh_flail_shield` `attack_slam` (shield slam, `light_attack_03`). `wh_2h_hammer`'s slams got descriptive labels ("Slam (special)" / "Slam (charged special)") rather than a raw fallback. All 55 dropdown OPTIONS are fully labeled (0 raw-fallbacks).

### Scope / safety
**3P-ONLY** — display-only change; no `anim_event_3p` write path, hook, or persist logic touched (`anim_event` / `wield_anim` / 1p units / `state_machine` never read or written). No new hooks (the picker still has none; VMF duplicate-hook rule respected). The hardcoded vocab, only-flagged membership filtering, character names, and the working apply path (`anim_event_3p` writes, `_ensure_setting_index_built`) are all preserved. 5 new file-scope symbols (`_SET_MOVE_LABEL`, `_SOURCE_MOVE_LABEL`, `_LABEL_SEP`, `_move_label_for_set`, `_move_label_for_source`); 47 file-scope locals total, 200-locals respected. mod-lint clean (0 forward-ref / late-local / duplicate-hook).

## 0.12.147-dev (2026-06-23) — 3P Anim Picker: picks now load from settings (empty `_setting_index` on the apply instance) — 3P-ONLY

The actual root cause behind every prior 3P-anim-picker miss (the .144 cache-bust and the .145 instrumentation were chasing the wrong layer): the apply path was iterating an **empty `_setting_index`**, so it never wrote anything to any template. The user's 0.12.146-dev instrumented log proved it — **zero `[wt:apply]` lines** for the entire session (neither boot `reapply_stored_picks` nor live `on_setting_changed` wrote anything), and every `[wt:play]` showed `picks_set={}`, `is_picked_3p_value=false`, `FINAL (unchanged)`, `has_anim=true`. The funnel was innocent (FINAL unchanged) and the clips existed (`has_anim=true`); the picks simply never reached the template because the runtime pick set was empty.

### Root cause — `mod:dofile` is NOT a singleton; the apply instance's index was never populated
`mod:dofile("…/wt_dev_anim_picker")` **re-executes the chunk and returns a fresh module table on every call** (it does not cache like `require`). The file is dofiled from **three** places, each getting its own private copy of the file-scope `_setting_index` upvalue:
- `weapon_tweaker.lua:139` — the **SCRIPT** instance (runs `install()` → `reapply_stored_picks()` at boot, and `mod.on_setting_changed` → `M.on_setting_changed()` on every live dropdown change),
- `weapon_tweaker_data.lua:1757` — the **DATA** instance (runs `build_widget_tree()`),
- `weapon_tweaker_localization.lua:1366` — the **LOC** instance (runs `loc_keys()`).

`_setting_index` is populated **only** inside `build_widget_tree()` (via `_build_attack_dropdown` → the per-attack rec write). That ran on the **DATA** instance only. The **SCRIPT** instance — the one that actually applies picks at boot and on change — never called `build_widget_tree()`, so its `_setting_index` stayed `{}`. `reapply_stored_picks()` iterated an empty table (zero applies); `on_setting_changed()` looked up `_setting_index[setting_id]`, got nil, and returned early (silent no-op). The dropdowns still showed the user's stored picks because VMF renders them straight off the settings store on the DATA instance — masking the empty SCRIPT-side index. This is the [[reference_vmf_mod_file_load_order]] / cross-instance-state class: shared state must live on the `mod` table or be rebuilt per-instance, never in a single dofile instance's upvalue. Setting-id symmetry was never the problem — the write-id and read-id are identical; the table they live in was the wrong (empty) one.

### Fix — make the index self-building on whichever instance needs it
New file-scope `_ensure_setting_index_built()` populates `_setting_index` from the same static catalog/attack tables **without** building any widgets (cheap, idempotent, guarded by `_setting_index_built`). The rec-write is factored into a shared `_register_attack_setting(entry, source_event)` used by **both** `_build_attack_dropdown` (DATA instance, building widgets) and `_ensure_setting_index_built` (SCRIPT instance, apply-only) so the rec shape can never drift between them. `reapply_stored_picks()` and `on_setting_changed()` now call `_ensure_setting_index_built()` first — so the SCRIPT instance's index is populated before it reads it, regardless of which dofile instance the entry point fired on. `build_widget_tree()` still fully populates the index as before and now marks `_setting_index_built = true` so a redundant rebuild on that same instance is a no-op.

### Expected log after this fix
Boot now emits `[wt:apply] … n>0` lines for every stored pick (was zero); a live dropdown change emits an `[wt:apply]` line immediately. `[wt:play]` should now show a non-empty `picks_set={…}` and `is_picked_3p_value=true` for picked attacks on the equipped picker weapon.

### Scope / safety
**3P-ONLY** — only `anim_event_3p` is read/written; `anim_event` / `wield_anim` / 1p units / `state_machine` are never touched. No new hooks (the picker module still has none; VMF duplicate-hook rule respected). The .144 MechanismOverrides cache-bust and the .145 `[wt:apply]`/`[wt:play]` instrumentation are **kept intact** — they're now meaningful because the apply path actually runs. New file-scope symbols: `_setting_index_built`, `_register_attack_setting`, `_ensure_setting_index_built`; `_build_attack_dropdown` slimmed to delegate. 200-locals respected. mod-lint clean (0 forward-ref / late-local / duplicate-hook).

## 0.12.146-dev (2026-06-23) — Inventory-preview wield pose for cross-character ports (3P-ONLY)

Fixes the missing wield stance in the keep inventory character preview for cross-character weapons whose `wt_wield_patches.lua` entry omits the previewed career's prefix — reported case **Elf Greatsword (`we_2h_sword`) on Kruber**, plus every other prefix-gap port (the fix is career-agnostic, not a one-off `es_*` add).

### Root cause
The previewer (`MenuWorldPreviewer`, derived from `HeroPreviewer`) fires the wield anim on the 3P body directly at spawn: `wield_anim_career_3p[career] -> wield_anim_career[career] -> item_template.wield_anim` (`world_hero_previewer.lua:1059-1066`). That path does **NOT** go through wt's `Unit.animation_event` redirect hook — the preview `character_unit` has no `career_system`/`inventory_system` extension, so `_unit_career_name(unit)` is nil in the hook and the `_career_anim_redirect` branch is a no-op there (gated on a resolved career). For `we_2h_sword` the template is `two_handed_swords_wood_elf_template`, whose wield patch lists only `wh_*`; on a Kruber `es_*` career `wield_anim_career_3p[es_*]` is nil, so the previewer fell back to the elf base `wield_anim = "to_2h_sword_we"` and fired it on Kruber's `empire_soldier` body, which does not author that elf event → no wield transition → the body holds its previous/idle stance (the "missing pose" symptom; no T-pose). In-mission is correct because `_career_anim_redirect.to_2h_sword_we` redirects it (alt `to_bastard_sword` on non-`we_` careers).

### Fix — receiver-native pose on the preview 3P body
Merged into the **existing** `MenuWorldPreviewer._spawn_item_unit` hook (no new hook — VMF duplicate-hook rule respected). After the engine spawns the unit, for the currently-wielded slot only (`self._wielded_slot_type == slot_type`, matching the engine's own gate so the off-hand isn't re-posed), it:
1. recomputes the event the engine fired (`wield_anim_career_3p[career]` → base `wield_anim`),
2. resolves the receiver-native target via the new `_resolve_preview_wield_event` helper, which re-uses the **same `_career_anim_redirect` data** (overrides → prefix/invert → alt) plus the suffix-redirect fallback the in-mission hook uses — **no parallel pose table**,
3. fires it on `self.character_unit` **only when** the resolved event differs from what was fired, the body does **not** author the fired event (i.e. it really was the missing-pose fallback), and the body **does** author the resolved event (`_safe_has_anim` guards both).

### Scope / safety
General fix for the whole prefix-gap class, not greatsword-only. **3P-ONLY**: the preview world has no 1P unit; only `self.character_unit` is touched; `anim_event`/`wield_anim`/1p units/`state_machine` are never read or written. Nil-guarded for preview spawn timing (`_is_unit`, `_safe_has_anim`, `pcall`-wrapped `Unit.animation_event`). No new locals near the 200 cap. New helper `_resolve_preview_wield_event` (file-scope, placed after `_try_suffix_redirect`). Diagnostic line `[wt:preview_wield]` logs each correction.

## 0.12.145-dev (2026-06-23) — 3P Anim Picker: LOGGING-ONLY play-path + apply-path instrumentation (no behavior change)

Diagnose-before-mitigate. The v0.12.144-dev cache-bust did not make picks visibly change the 3P animation in-game, and the structural "write reaches engine" analysis has been wrong twice. This build adds **logging only** to the apply path and the runtime play path so the next attack logs exactly where a picked animation is lost. No behavior fix; no 1P paths touched.

### Override-hypothesis verdict (investigated, then instrumented to confirm/refute in-game)
For the prime suspect — `dr_2h_pick` (`two_handed_picks_template_1`) wielded by a Kruber career — the runtime redirect funnel does **NOT** rename a picked event. Traced in source: the pickaxe's Kruber wield event is `to_2h_hammer` (`wt_wield_patches.lua:194`), which is **not** a key in `_3p_remap_triggers`; `two_handed_picks_template_1` has **no** entry in `_3p_template_remaps`; key `dr_2h_pick` has none in `_3p_key_remaps`; and the fallback `_resolve_3p_remap("to_2h_hammer", career)` returns nil — so `state.remap` stays nil and the attack-remap / flail / career-redir / suffix branches all fall through. The picked `anim_event_3p` value reaches `Unit.animation_event(owner_unit, <picked>)` unchanged. Separately, `MechanismOverrides` returns the **original live** `two_handed_picks_template_1` table (the template carries no `mechanism_overrides` field, and neither do its actions — only `packmaster_claw` does in `weapon_templates/`), so for the pickaxe the cache-bust is a no-op and the engine reads the picker's live writes directly. **Conclusion:** the loss is NOT the funnel and NOT the MechanismOverrides cache for this weapon — it is upstream (apply-side) or a content limitation (Kruber body doesn't author/visibly play the picked clip). The instrumentation distinguishes these.

### `[wt:apply]` — apply-path trace (always logged, both live `on_setting_changed` and boot `reapply_stored_picks`)
`_apply_anim_event_change` now `mod:info`s `[wt:apply] tpl=… source_event=… -> anim_event_3p=… n=… sites={action.sub,…}` on every write — proving (a) the write reached the template the wielded weapon uses and (b) the COUNT of sub-actions matched + the exact `action.sub_action` sites written (n>0). When `n==0` it additionally dumps the live template's full `anim_event`/`anim_event_3p` vocab (`_live_anim_event_vocab`) so a stale-`_WEAPON_ATTACKS` source-string mismatch is diagnosable from the log alone.

### `[wt:play]` — runtime play-path trace (LOCAL 3P body, picker weapons only, gated on the picker toggle)
New block in the `Unit.animation_event` hook (`weapon_tweaker.lua`). Scoped to: `is_local` 3P body, a combat event (`attack_`/`push_`/`parry_`), `enable_dev_anim_picker` ON, and `state.template` being one of the picker's flagged templates (`_wt_dev_anim_picker.is_picker_template`). It logs:
- `[wt:play] READ event=… tmpl=… key=… career=… is_picked_3p_value=… has_anim=… picks_set={src->val,…}` — the event the ENGINE read for this swing. On the 3P body the engine fires the picked `anim_event_3p` VALUE directly (`weapon_unit_extension.lua:512`), so `is_picked_3p_value=true` means the pick reached the engine; `false` means it was lost upstream (apply n==0 / wrong template / never written). `has_anim` reports whether the Kruber skeleton even authors that clip.
- `[wt:play] FINAL event=… (read was …) <<RENAMED BY FUNNEL>> | (unchanged) has_anim=…` — emitted via a per-call wrapper on the hook's `func`, so EVERY downstream fire in the hook reports the FINAL event handed to the engine. If wt's funnel renamed the picked event, the FINAL line differs and names it (override hypothesis, confirmed/refuted per swing). (The one FORCE path calling `_original_animation_event` directly is gated on `state.remap == spear_to_billhook`, which never applies to a picker weapon, so wrapping `func` is complete coverage here.)

### Reading the log
(a) Did the pick get written to the wielded template? → `[wt:apply] … n>0` with the right `tpl=`. (b) Did the engine read the picked value? → `[wt:play] READ … is_picked_3p_value=true`. (c) Did the funnel rename it before it played? → `[wt:play] FINAL … <<RENAMED BY FUNNEL>>` (or `(unchanged)`). If READ shows `is_picked_3p_value=true`, FINAL is `(unchanged)`, and `has_anim=true`, the pick fully reaches the engine and the remaining gap is purely a 3P-clip / state-machine playability issue on the Kruber body (not a code bug).

### Preserved / scope
LOGGING ONLY — no apply/redirect behavior changed. 3P-ONLY: reads/writes only `anim_event_3p`; never `anim_event` / `wield_anim` / 1p units / `state_machine`. No hooks added (the picker module still has none; the play-path log lives inside the existing single `Unit.animation_event` hook — VMF duplicate-hook rule respected). New picker exports: `is_picker_template`, `current_3p_for`, `live_3p_map`, `is_picked_3p_value`, plus `_live_anim_event_vocab`. 200-locals respected.

## 0.12.144-dev (2026-06-23) — 3P Anim Picker: picks now actually apply in 3P (MechanismOverrides cache-bust)

All 3P-only. Fixes the dev `wt_dev_anim_picker.lua` so a per-attack pick takes effect on the equipped weapon. The write target was already correct (`anim_event_3p` on the live `Weapons[name]` sub-actions); the disconnect was a caching layer between that write and the engine read.

### Root cause — the engine reads a CACHED COPY, not the live template
At attack time the engine resolves the action's 3P anim from `MechanismOverrides.get(rawget(Weapons, name))`, not the live `Weapons[name]` table the picker mutates (`Vermintide-2-Source-Code/scripts/helpers/weapon_utils.lua:211` → `backend_interface_item_playfab.lua:871` → `backend_utils.lua:136` → `WeaponUnitExtension.start_action` reads `current_action_settings.anim_event_3p` per swing). `MechanismOverrides.get` (`.../game_mode/mechanisms/mechanism_overrides.lua:13`) shallow-COPIES any template that carries a `mechanism_overrides` field (or has a nested child that does) and caches the copy in `CACHE[t]`, persisting it for the whole mechanism. Once cached, every `get_item_template` returns the stale COPY — so a menu-time write to the live original was never seen by an attack. The existing `_try_force_rewield` re-runs `inv:wield(slot)` but does NOT invalidate that cache, so the rewield re-read the same stale copy.

### Fix — bust the MechanismOverrides cache after every write, then rewield
New file-scope helper `_bust_mechanism_override_cache(template_name)` (`wt_dev_anim_picker.lua`) calls `MechanismOverrides.recursive_cleanup(Weapons[name], current_mechanism_name)` (`mechanism_overrides.lua:119`) to drop `CACHE[t]`, forcing the next `get_item_template` to rebuild the copy from the now-mutated live template. It's a guarded no-op (`if original then` at `mechanism_overrides.lua:122`) when the template was never cached (e.g. a template with no overrides anywhere in its tree), so it's safe to call unconditionally. `_apply_anim_event_change` now calls it after the mutation loop — for BOTH the live `on_setting_changed` path (cache-bust THEN `_try_force_rewield`, order matters) and the boot `reapply_stored_picks` path. No re-equip required: the cache-bust makes the live write take on the next attack; the rewield just forces an immediate refresh.

### Fix — loud no-op-write warning
`_apply_anim_event_change` now `mod:warning`s when a write matches zero sub-actions (`n == 0`) instead of returning silently. A zero-match means the hardcoded `_WEAPON_ATTACKS` source string doesn't match any live `anim_event` on that template's sub-actions, so the dropdown writes nothing — previously this was invisible. The message points at `/wt_coverage` + `/wt_dump_anim_picks` to reconcile a stale source list.

### Preserved
Hardcoded-vocab simplification (`_WEAPON_SET` / `_SET_VOCAB` / `_WEAPON_ATTACKS`), only-flagged membership filter (`wt_port_status.needs_anims` allow-list), character-named source qualifiers + `Kruber` receiver, the live-submenu pattern, `/wt_dump_anim_picks` + `/wt_coverage`. No hooks added (VMF duplicate-hook rule — the module still has none). 3P-ONLY: the fix touches only `anim_event_3p` — never `anim_event` / `wield_anim` / 1p units / `state_machine`. 200-locals respected (one new file-scope local).

## 0.12.143-dev (2026-06-23) — 3P Anim Picker rebuilt as a STATIC hardcoded menu (no set-chooser, no dynamic resolution)

All 3P-only. The dev `wt_dev_anim_picker.lua` is rewritten from a dynamic catalog/vocab walk + a per-weapon 3P anim-SET chooser into a fully STATIC hardcoded menu, per the v0.12.143-dev spec. No 1P field is read or written.

### Removed — the per-weapon 3P anim-SET chooser dropdown + all dynamic-resolution code
The established SET per weapon is fixed (resolved offline from `wt_wield_patches.lua` → the `to_*` wield event → its target template), so the set is no longer negotiated in-menu. Deleted: `_build_set_dropdown`'s set-dropdown, `_build_kruber_set_options`, `_KRUBER_SET_LABEL` / `_set_friendly`, the `_WIELD_EVENT_TO_TARGET` / `_WIELD_TARGET_BY_RECEIVER` maps + `_resolve_target_for_port` / `_live_target_template_for`, the `_build_dynamic_catalog` unlock-map walk + `_build_chooser_catalog`, the Kruber-only vocab build (`_build_kruber_native_templates` / `_build_kruber_wield_vocab` / `_live_wield_vocab`), the `_pre_apply_wield_patches` / `wt_wield_patches` dofile (the picker no longer needs to pre-seed `wield_anim_career_3p` to resolve targets), the `_GREATHAMMER_BASELINE_*` seed tables, the `kind="wield"` apply path (`_apply_wield_change`) + the wield `setting_id` factories (`_sid_set` / `_sid_set_group` / `_sid_wield`). The `wt_unlock_data` dofile is also gone (membership is now the explicit allow-list, not a unlock-map walk).

### Added — three static hardcoded tables drive the whole picker
`_WEAPON_SET` (weapon_key → established SET letter A..E), `_SET_VOCAB` (SET → the target template's authored `anim_event` vocab = the dropdown OPTIONS, 11 per set, identical for every weapon in that set), and `_WEAPON_ATTACKS` (weapon_key → the weapon's own source attack `anim_event`s, one dropdown each). Plus `_WEAPON_TEMPLATE` (source template per weapon) and a curated `_WEAPON_NAME`. The five sets: A Greathammer (`to_2h_hammer` / `two_handed_hammers_template_1`), B Mace & Sword (`to_dual_hammer_sword_es` / `dual_wield_hammer_sword_template`), C Empire 1H Sword (`to_1h_sword` / `one_handed_swords_template_1`), D Mace & Shield (`to_1h_hammer_shield` / `one_handed_hammer_shield_template_1`), E Witch Hunter 1H Axe (`to_1h_axe` / `one_hand_axe_template_1`). Set vocabs + per-weapon source attacks were extracted from + verified against the decompiled `Vermintide-2-Source-Code/.../weapon_templates/` files.

### Menu shape
Per flagged weapon → one collapsible `type="group"` (label `"<Source> <Weapon> rendered on Kruber body  [<set>]"`), with one per-attack `anim_event_3p` dropdown inside whose OPTIONS are the HARDCODED established-set vocab. Selecting one applies via `_apply_anim_event_change` (writes `anim_event_3p` ONLY — 3P), auto-rewields, persists, and boot-replays — unchanged. A handful of source attacks with no clean target-set twin (`attack_swing_right_spell` on `bw_flame_sword`; `attack_slam`/`attack_slam_charge` on `wh_2h_hammer` + `wh_flail_shield`; `special_action`/`special_action_02` on `bw_ghost_scythe`) still get a dropdown — the user maps to the nearest set event or leaves UNSET (falls through to the prior idle stance; no T-pose, no crash).

### Preserved
- Live-submenu pattern intact (`build_widget_tree()` returns the ARRAY of per-weapon group widgets, nested as the `enable_dev_anim_picker` checkbox's `sub_widgets`; VMF reveals/hides LIVE on toggle — no restart). Lightweight build (now trivially cheap — static-table copy, no IML/catalog/vocab walk). Character-named source qualifiers + `Kruber` receiver. The group → dropdown nesting keeps the gut Mod Tweaker depth-drill working. `/wt_dump_anim_picks` + `/wt_coverage` retained (Kruber-scoped). No status tags on rows (the `[set]` bracket is the chosen-animation-set name, not a status tag). No hooks (VMF duplicate-hook rule — the module has none). 3P-ONLY throughout. 200-locals respected (35 file-scope locals).

### Membership
Gated on `wt_port_status.M.needs_anims(career, weapon_key)` — the explicit `_NEEDS_ANIMS.kruber` allow-list (15 weapons). Verified: the picker's 15 hardcoded weapons EXACTLY match `_NEEDS_ANIMS.kruber`; every weapon has a non-empty source-attack list; every set has 11 options — so every flagged weapon's dropdowns are non-empty.

## 0.12.142-dev (2026-06-23) — Picker/Availability refinements: tags moved to Availability (+redirect target), character-named sources, picker lists only flagged weapons

All 3P-only. Four refinements from `KRUBER_3P_ANIM_DECISIONS.md` § OPEN ISSUES. No 1P field is read or written.

### Changed (1) — REMOVED status-tag prefix from the PICKER
Every picker row needs animations by definition, so the `[Needs Animations] ` / `[Needs Offsets] ` prefix was noise there. The `_chooser_prefix(entry)` helper and its single call site (the `_sid_set_group` label in `M.loc_keys`) are gone (`wt_dev_anim_picker.lua`). Picker rows now read just `<character> <weapon type> rendered on … [chosen set]`. The `[chosen set]` bracket stays — it's the chosen-animation-set name (e.g. `[Empire Greathammer]`), the thing the user picks, NOT a status tag.

### Changed (2) — Status + REDIRECT TARGET now on the WEAPON AVAILABILITY menu
`wt_port_status.lua` gains `M.redirect_target(career, weapon_key)` → the bracketed target weapon a `[Needs Animations]` port borrows its 3P anims from (e.g. `[Greathammer]`), sourced from a new `_NEEDS_ANIMS` table (the `SET=` column of `ANIMATION_COVERAGE.md` "## Receiver: KRUBER"). The localization post-process loop (`weapon_tweaker_localization.lua`) now folds that target into the tag for a `[Needs Animations]` port: a row reads `[Needs Animations → Greathammer] Kruber: …`. `[Working]` (fully functional — no redirect), `[Needs Offsets]`, and `[Untested]` carry no redirect and read plainly. So each Availability row shows BOTH what it needs AND which weapon's 3P animation it borrows.

### Changed (3) — PICKER source qualifier uses CHARACTER names, not race names
`_SOURCE_QUALIFIER` (`wt_dev_anim_picker.lua`) remapped `Empire/Dwarf/Elf/Witch Hunter/Bright Wizard` → `Kruber/Bardin/Kerillian/Saltzpyre/Sienna`, matching the Availability menu ("Kruber: Mace", "Bardin: Great Axe"). "Dwarf Pickaxe" now reads "Bardin Pickaxe". `_QUALIFIER_OVERRIDES` emptied: `es_sword_shield_breton` falls through to "Kruber" (Bretonnian is a weapon descriptor, not a source character); the three `wh_*` Warrior-Priest weapons resolve to "Saltzpyre" via the `wh_` owner prefix (no override needed). The receiver short name (`_CHARACTER_SHORT`) was already character-named — unchanged.

### Changed (4) — PICKER lists ONLY explicitly-flagged `[Needs Animations]` weapons
The chooser used a NEGATIVE filter ("every Kruber port not confirmed and not `[Working]`"), which surfaced UNTESTED ports too — Beam Staff (`bw_skullstaff_beam`), Javelin, Deepwood Staff were never flagged yet appeared. Replaced with a POSITIVE allow-list: `wt_port_status.M.needs_anims(career, weapon_key)` is true only for the explicit `_NEEDS_ANIMS` Kruber set (the `SET=`-annotated `📋`/`🔧` rows from `ANIMATION_COVERAGE.md` + `KRUBER_3P_ANIM_DECISIONS.md`). Untested + confirmed + needs-offsets-only ports all fall out; `bw_ghost_scythe` (needs anims AND offsets) correctly stays. The redundant `_COVERAGE_CONFIRMED_KRUBER` exclusion mirror was deleted — a confirmed port is simply absent from `_NEEDS_ANIMS`, collapsing two divergent confirmed-lists into one source of truth in `wt_port_status.lua`.

**Decision (item 4 open question):** did NOT flip `M.tag`'s default-return from `[Needs Animations]` to `[Untested]`. That would have re-tagged ~100 un-cataloged Availability ports (a visible behavior change). Instead the picker gates on an EXPLICIT closed allow-list, satisfying "list ONLY flagged weapons" with zero change to the Availability menu's existing tags.

### Preserved
- Live-submenu pattern intact (picker rows are still the `enable_dev_anim_picker` checkbox's `sub_widgets`; VMF reveals/hides LIVE on toggle). Kruber-only lightweight vocab build unchanged (no ~11 MB six-character leak). v0.12.141 weapon-TYPE naming fix (curated `_WEAPON_NAME`) intact. Dropdown population unchanged. No new hooks (VMF duplicate-hook rule); the tag/redirect work is pure data + a localization post-process. 200-locals respected.

## 0.12.141-dev (2026-06-23) — Picker names by weapon TYPE (no cosmetic-illusion leak/overflow) + every Weapon-Availability entry computed-tagged

All 3P-only. Fixes the two user-reported issues from `KRUBER_3P_ANIM_DECISIONS.md` § OPEN ISSUES (picker wrong-names/empty-dropdowns/overflow; Availability tags incomplete). No 1P field is read or written anywhere in this change.

### Fixed — picker showed COSMETIC-ILLUSION names ("Dwarf Beardling's Azdrek"), not weapon TYPES (+ row overflow)
`_weapon_display_name` (`wt_dev_anim_picker.lua:689`) resolved the name via `_weapon_loc_name` FIRST, which reads `ItemMasterList[key].localized_name`. On a base weapon-TYPE key that field is the **default cosmetic SKIN's** name, not the weapon-type name — `ItemMasterList.dr_2h_pick.display_name = "dw_2h_pick_skin_01_name"` → "…Azdrek"; `ItemMasterList.es_handgun.display_name = "es_handgun_skin_03_name"` `[src: Vermintide-2-Source-Code item_master_list_exported.lua:7501, :6797; item_master_list.lua:114 (localized_name = Localize(display_name))]`. So the curated weapon-TYPE map `_WEAPON_NAME` was never consulted (the `or` short-circuited), leaking long cosmetic names that also overflowed the row.

**Fix — reverse the precedence:** `_WEAPON_NAME[weapon_key]` (the deduped, one-entry-per-weapon-TYPE source of truth) wins; `_weapon_loc_name` is now a LAST-resort fallback only for keys `_WEAPON_NAME` doesn't cover (flagged via `_OPEN_QUESTIONS`). Same fix applied to the TARGET side (`_target_loc_display:676`): curated name / hand-written `display` fallback wins over the reverse-mapped base key's cosmetic `localized_name`. Same type-vs-illusion trap as `reference_vt2_versus_items_hidden_in_adventure` (vs_* keys carry cosmetic-grade strings).

This is the type-vs-illusion distinction the task asked to DOCUMENT: a clarifying block at the enumeration site (`_build_dynamic_catalog`) now states ItemMasterList holds weapon TYPES **and** cosmetic skins/illusions, that the picker enumerates one-row-per-TYPE off `weapon_unlock_map` (NOT a raw IML walk), and that the cosmetic name only ever leaked at the DISPLAY step. The doctrine is also recorded in `docs/MECHANICS.md`.

### Fixed — empty per-attack dropdowns: runtime diagnostic to name the exact coverage gaps
A Kruber chooser row shows NO per-attack dropdowns exactly when its live wield set fails to resolve a target template (`_build_set_dropdown` gate) — i.e. its SOURCE template has no `es_*` career in `wt_wield_patches.lua`, or the resolved wield event has no `_WIELD_*_TO_TARGET` entry. Offline scans can't reliably resolve weapon_key→template (the IML is split across many files and base keys carry no `template` field), so `_ensure_catalog_built` now walks the LIVE data (where both resolutions exist) and logs each unresolved Kruber chooser row by `weapon_key(src=template,wield=event)`. The user's next boot log names precisely which source template needs an `es_*` patch add — mirroring the v0.12.140-dev `we_one_hand_axe_template` fix — instead of a guess. (Every currently-catalogued `[Needs Animations]` Kruber row already resolves via the existing patches; the diagnostic guards against regressions + future ports.)

### Fixed — Weapon-Availability tags were INCOMPLETE (299 of 947 entries bare; confirmed ports mislabeled)
The `unlock_*` labels in `weapon_tweaker_localization.lua` carried HAND-TYPED tag prefixes (`[untested]` / `[confirmed working]` / bare). 299 entries had no tag, and confirmed ports read wrong: **Saltzpyre's Flail** (`es_1h_flail`) was bare on Kruber and `[untested]` on Saltzpyre's careers; **Bardin's Greataxe** (`dr_2h_axe`) was `[untested]` on its cross-character rows. There was no status-computation layer — the tag was free text typed per string.

**Fix — computed tags from real status (new `wt_port_status.lua`).** A shared `(career, weapon_key) -> tag` resolver, generated 2026-06-23 from `ANIMATION_COVERAGE.md` (✅/🔁 → `[Working]`; ❓ → `[Untested]`; grip rows → `[Needs Offsets]`) merged with `KRUBER_3P_ANIM_DECISIONS.md` CONFIRMED rows and the picker's `_COVERAGE_CONFIRMED_KRUBER` / `_PORT_STATUS_LABEL`. The localization file now post-processes every `unlock_*` entry: strip any leading hand-typed `[…]` tag and prepend the computed one (vocabulary `[Working]` / `[Needs Animations]` / `[Needs Offsets]` / `[Untested]`). Native ports (owner prefix == receiver, incl. WP wielding the wh_* family) → `[Working]`; the default for a surviving cross-character port (set decided, per-attack pending) → `[Needs Animations]`. Saltzpyre's Flail now reads `[Working]` everywhere (native on Kruber/Saltzpyre, confirmed elsewhere); Bardin's Greataxe `[Working]` on every receiver. No weapon is untagged. This replaces three divergent hand-typed vocabularies with ONE source the Availability menu + picker now share.

### Preserved
- Live-submenu pattern intact: the picker rows are still the `sub_widgets` of the `enable_dev_anim_picker` checkbox (VMF reveals/hides LIVE on toggle, no restart). The Kruber-only lightweight vocab build is unchanged — no ~11 MB six-character leak re-introduced. No new hooks (VMF duplicate-hook rule); the tag pass is a pure data post-process at localization-load time. 200-locals respected (the tag loop's locals are in the localization chunk; no per-frame Query/View work).

## 0.12.140-dev (2026-06-23) — 3P Anim-Set Chooser becomes a LIVE master toggle (no restart) + Kerillian 1H Axe coverage gap closed

All 3P-only. Reworks the dev 3P Anim-Set Chooser (Kruber) into a fully-functional per-attack picking menu that reveals LIVE when toggled — the "needs a game restart" dead-toggle bug is gone.

### Fixed — `enable_dev_anim_picker` was a dead toggle (required a restart to take effect)
The picker's widget tree was built ONCE at boot, gated on the toggle's value AT BOOT, and VMF never re-runs `_data.lua` — so flipping the toggle at runtime did nothing (the tooltip even admitted "then restart the game"). Root cause chain: `enable_dev_anim_picker` was a standalone top-level checkbox with no children; the picker entries were a SEPARATE top-level group appended only when `build_widget_tree()` returned non-nil; `build_widget_tree()` returned nil when the toggle was OFF at boot because `_ensure_catalog_built()` short-circuited to an empty catalog; `_catalog_built` latched so it never re-evaluated.

**Fix — VMF native master-toggle → `sub_widgets` (reference_vmf_native_master_toggle_submenu).** The picker rows are now nested as the `sub_widgets` of the `enable_dev_anim_picker` CHECKBOX, built UNCONDITIONALLY at boot, and VMF's per-frame visibility loop (`vmf_options_view.lua:4461-4463`) reveals/hides the whole picker menu LIVE when the box is toggled — no restart. VMF reads `mod:get` itself each frame to drive visibility, so the `mod:get`-based toggle still controls the picker; it's just no longer a Lua gate that latched at boot. The OFF short-circuits in `_ensure_catalog_built()`, `_build_dynamic_catalog()`, and `M.loc_keys()` are removed; the dead `_dev_picker_enabled()` helper is removed.

### Changed — `build_widget_tree()` returns an ARRAY, not a wrapping group
`M.build_widget_tree()` (`wt_dev_anim_picker.lua`) now returns the array of per-Kruber-port set-dropdown group widgets directly (never a top-level group, never nil). `weapon_tweaker_data.lua` nests that array as the checkbox's `sub_widgets` (guarded: attaches only when non-empty, else a bare checkbox — empty `sub_widgets` is tolerated on a checkbox; only `type="group"` rejects zero children). All per-port group labels / dropdown labels / per-attack option texts are registered at boot regardless of the toggle (`M.loc_keys()` no longer early-returns when OFF) so the revealed widgets never render `<<key>>`.

### Changed — LIGHTWEIGHT Kruber-only vocab build (no ~11 MB leak despite building unconditionally)
Building the picker at boot regardless of toggle would re-introduce the ~11 MB six-character vocab leak the old boot-gate existed to suppress. So the heavy builders (`_build_native_templates_by_char` walked all of `ItemMasterList`; `_build_live_wield_vocab` / `_build_live_anim_event_vocab` walked every `es_/dr_/we_/wh_/bw_` native template tree for all six characters) are REMOVED and replaced with a Kruber-only build:
- `_build_kruber_native_templates()` — one `ItemMasterList` pass keeping only `es_`-prefixed templates.
- `_build_kruber_wield_vocab()` — the ~14 Kruber `to_*` wield-set strings (the only vocab the set dropdown consumes via `_build_kruber_set_options`).
- `_live_anim_event_vocab` left EMPTY — the per-attack dropdowns pull each TARGET template's vocab lazily (`_collect_target_anim_event_vocab`), not the per-character anim_event vocab. The six-char anim_event vocab was dead weight for the chooser.

Net resident cost: one `es_`-only IML pass + ~14 Kruber wield strings + N Kruber port rows, each lazily pulling one target template's ~20-event vocab — instead of six full character vocabularies + a full IML native map.

### Fixed — Kerillian 1H Axe (`we_1h_axe` → Kruber) coverage gap (`wt_wield_patches.lua:199`)
`we_one_hand_axe_template` had ONLY `wh_*` careers, so for Kruber `wield_anim_career_3p[es_huntsman]` was nil → `_resolve_target_for_port` returned nil → the row read `[Needs Offsets]` and built NO per-attack dropdowns. Added the four `es_*` careers (`= "to_1h_axe"`); on Kruber `to_1h_axe` resolves via `_WIELD_TARGET_BY_RECEIVER.es` → `one_hand_axe_template_1` (Witch Hunter 1H Axe vocab), moving it into the `[Needs Animations]` set. This was the single gap; every other catalogued `[Needs Animations]` Kruber weapon already resolved.

### Preserved
- Per-attack `anim_event_3p` dropdowns (one per source attack action, options = the resolved target-set 3P vocab), the `[Needs Animations]` / `[Needs Offsets]` prefix + `[Set]` suffix labels, and the Greathammer baseline pre-fill for War Pick / Coghammer / Reckoner — all unchanged from 0.12.139-dev.
- Picks still apply LIVE via `_apply_anim_event_change` / `_apply_wield_change` (3P-only — `anim_event_3p` / `wield_anim_career_3p`, never 1P) + `_try_force_rewield` + boot `reapply_stored_picks`. No new apply code; the `^wt_dev_anim_` dispatch in `weapon_tweaker.lua` already forwards the child ids.

### Weapons rendered (13 `[Needs Animations]` Kruber rows, per-attack dropdowns)
War Pick (`dr_2h_pick`), Coghammer (`dr_2h_cog_hammer`), Reckoner Greathammer (`wh_2h_hammer`), Sword & Dagger (`we_dual_wield_sword_dagger`), Sienna's Dagger (`bw_dagger`), Dual Skullsplitters (`wh_dual_hammer`), Kerillian Dual Swords (`we_dual_wield_swords`), Dual Axes (`dr_dual_wield_axes`), Sienna's Mace (`bw_1h_mace`), Sienna's Scythe (`bw_ghost_scythe`), Kerillian Glaive (`we_2h_axe`), Sienna's Fire Sword (`bw_flame_sword`), WP Flail & Shield (`wh_flail_shield`) — plus Kerillian 1H Axe (`we_1h_axe`) now that the gap above is closed (14 total).

## 0.12.139-dev (2026-06-23) — KRUBER decisions merge: chooser per-attack dropdowns + `[Needs Animations]` prefix + Volley/Repeater-Crossbow crash fix

All 3P-only. Three changes from the verified `KRUBER_3P_ANIM_DECISIONS` capture.

### Fixed (game-breaking, network game) — Kerillian Repeater Crossbow (`we_crossbow_repeater`) on Kruber empty-wield crash
Wielding the ported elf Repeater Crossbow EMPTY/unloaded on a Kruber career fired the not-loaded/no-ammo wield events — `to_repeating_crossbow_elf` / `to_repeating_crossbow_elf_noammo` (`repeating_crossbows_elf.lua:258-259`) — which are **absent from `NetworkLookup.anims`** (the lookup has `to_repeating_crossbow`/`_noammo` and `to_repeating_handgun`/`_noammo`, but **no `_elf` entries**). The empty-wield path routes the not-loaded event through `ammo_extension:start_reload(...)` → `generic_ammo_user_extension.lua:311-330`, where `event_id = NetworkLookup.anims[reload_event]` is `nil` and `network_transmit:send_rpc_clients("rpc_anim_event", nil, go_id)` packs nil into a network-typed lookup-index field → **C-level RPC-packer fatal (bypasses pcall, network game only)**. wt's `_WIELD_ANIM_CAREER_3P_PATCHES_BULK` only patched the LOADED `wield_anim_career_3p` (consumed via the safe non-networked `Unit.animation_event` path), not the not-loaded/no-ammo wields.

**Fix:** new `_NOT_LOADED_NO_AMMO_CAREER_PATCHES` + applier (`weapon_tweaker.lua`, after the wield-patch apply) writes `wield_anim_not_loaded_career` / `wield_anim_no_ammo_career` for the four Kruber careers on `repeating_crossbow_elf_template` → `to_repeating_handgun` / `to_repeating_handgun_noammo` (both **registered** in `NetworkLookup.anims` AND authored on Kruber's `empire_soldier` 3P body). 3P wield-fallback fields only — never `anim_event`/`wield_anim` (1P). Native Kerillian wielders are untouched (only `es_*` careers patched). NOT fixed by registering the `_elf` names into `_anim_redirect` (those redirect onto the same unregistered events and carry the identical latent crash for non-elf wielders). Saltzpyre's Volley Crossbow (`wh_crossbow_repeater`) never crashed — its template uses the registered `to_repeating_crossbow`/`_noammo` not-loaded wields.

### Added — per-ATTACK 3P-anim dropdowns under each chooser row (`wt_dev_anim_picker.lua`)
The Kruber 3P Anim-Set Chooser now adds one per-attack `anim_event_3p` dropdown (a bare dropdown emitted directly into the set group's `sub_widgets`, alongside the set dropdown) for each **set-decided** port (the wield set resolves to a target template). Options = the chosen target template's authored `anim_event` vocab (target-filtered; broad receiver vocab fallback if the target authors none). Reuses the dead-but-present `kind="anim_event"` machinery verbatim — `_apply_anim_event_change` writes `anim_event_3p` ONLY (3P), plus `_try_force_rewield` / `reapply_stored_picks` for live-apply + persist + boot-replay. No new apply code, no main-file edit (`^wt_dev_anim_` dispatch at `weapon_tweaker.lua:4565` already forwards the new ids). Per-attack vocab is resolved from the **live** wield set (`_live_target_template_for`), so it tracks chooser set-picks on the next menu re-open (catalog is built once; VMF can't rebuild widgets mid-frame — stated in the tooltip).

**Load-order fix (the enabler).** The picker's `build_widget_tree()` / `loc_keys()` run from `_data.lua` / `_localization.lua`, which VMF loads BEFORE the main script's top-level patcher calls (`reference_vmf_mod_file_load_order`). So at catalog-build time the live `Weapons.*.wield_anim_career_3p` was still empty (vanilla cross-character templates carry none), `_resolve_target_for_port` returned nil for every patcher-decided port, and NO port would have shown a target/per-attack surface. Fix: the two cross-character wield-patch tables (`_WIELD_ANIM_CAREER_3P_PATCHES` + the 72-entry `_BULK`) were extracted **verbatim** (byte-identical; key+pair-diff-verified) into a new shared module `wt_wield_patches.lua` that BOTH the main script and the picker `mod:dofile`. The picker pre-applies them to `Weapons.*` at catalog-build time (`_pre_apply_wield_patches`, only when the picker is ON, seed-if-absent so it never clobbers), idempotent with the main script's later apply. This also fixes the latent v0.12.138 bug where the chooser's "using X animations" label silently never resolved for patcher-decided ports.

- **`[Needs Animations]` / `[Needs Offsets]` row prefix.** A set-decided row reads `[Needs Animations] <Weapon> [<Set>]` (per-attack picks still pending); an undecided row keeps `[Needs Offsets]`. Refreshes on menu re-open (VMF caches the open label).
- **Greathammer BASELINE pre-fill.** The three Greathammer-family ports — War Pick (`dr_2h_pick`), Coghammer (`dr_2h_cog_hammer`), Reckoner (`wh_2h_hammer`) → all SET=`to_2h_hammer`/Empire Greathammer — seed their per-attack dropdown DEFAULTS from a hand-mapped Empire Greathammer (`two_handed_hammers_template_1`) vocab (light diagonals→`attack_swing_left_diagonal`, heavy overheads→`attack_swing_down_left`/`_right`, heavy sweeps→`attack_swing_heavy`/`_heavy_right`, charge wind-ups→`attack_swing_charge`L/R, push→`attack_push`, block→`parry_pose`, wield→`to_2h_hammer`). Only seeds when the live template hasn't set an `anim_event_3p` for that source attack — never overwrites a live/persisted pick. User tweaks live.

### Changed — `ANIMATION_COVERAGE.md` chooser-exclusion mirror (`_COVERAGE_CONFIRMED_KRUBER`)
Capture-confirmed two more Kruber rows to ✅ → added to `_COVERAGE_CONFIRMED_KRUBER` (drops them out of the chooser next boot): `dr_shield_axe` (Axe & Shield, native fall-through) and `bw_1h_flail_flaming` (Flaming Flail, wield redirect). `bw_1h_crowbill` is **HELD** out of the exclusion pending user reconcile — the capture says CONFIRMED but `ANIMATION_COVERAGE.md:59` still flags a Kruber heavy-attack regression (🧊). Coverage doc B-rows updated to `[Needs Animations] … (SET as tabled)`; the elf-vs-volley crossbow FALSE-event note corrected (the crasher is the elf `we_crossbow_repeater`, not the registered-event Volley `wh_crossbow_repeater`).

### NOT in this pass (deferred)
- **MODEL-SUB ports** (`wh_hammer_book` Skullsplitter & Tome, `wh_fencing_sword` Rapier & Pistol) — separate later pass (mesh hide + native-anim route); NOT surfaced as plain chooser rows.
- **`bw_1h_crowbill`** exclusion — awaiting user retest of the heavy-attack regression.

## 0.12.138-dev (2026-06-23) — 3P Anim-Set Chooser (Kruber) replaces the per-attack picker + dead-toggle/leak fix

### Fixed (two root causes behind the dev-picker memory regression)
- **RC2 — dead toggle.** `_dev_picker_enabled()` (`wt_dev_anim_picker.lua`) read the engine `Application.user_setting("mods_settings", "wt", ...)` store, where VMF does NOT persist checkbox settings — so it always returned nil and the `enable_dev_anim_picker` toggle was inert (the gate never engaged). Now reads `mod:get("enable_dev_anim_picker")` (the VMF store; `mod` is valid at `_data.lua`/`_localization.lua` boot time). The widget + loc keys were already correct.
- **RC1 — gate hoisted above the leak sources.** The old gate only short-circuited `_build_dynamic_catalog`, AFTER `_build_native_templates_by_char` (walks all of `ItemMasterList`) + `_build_live_wield_vocab` / `_build_live_anim_event_vocab` (walk every `es_/dr_/we_/wh_/bw_` native template tree) had already run. The gate now short-circuits at the TOP of `_ensure_catalog_built()` (empty catalog + empty vocabs when OFF) and `M.loc_keys()` early-returns the single top-level loc string when OFF. OFF now = `+0.0 MB` on the `[mem-probe]` lines.

### Changed (the live tuning surface — replaces the per-attack picker)
The per-attack dropdown fan-out (one dropdown per source `anim_event` × six characters) is replaced by a **Kruber-only 3P Anim-Set Chooser**:
- **One dropdown per non-confirmed Kruber cross-character port** (flat list, no per-character sub-buckets). Options = the live Kruber-native `to_*` wield sets (data-driven from `_live_wield_vocab.kruber`), each shown with a friendly label (`_KRUBER_SET_LABEL`, e.g. `to_2h_billhook` → "Empire Billhook"), plus an "(unset — fall through)" sentinel. Rows sorted A→Z by label.
- **Exclusion = confirmed-working, sourced from `ANIMATION_COVERAGE.md`.** A port is shown iff it's a Kruber cross-character port in the dynamic catalog AND not `[Working]` in-code AND not in `_COVERAGE_CONFIRMED_KRUBER` (the generated mirror of the ✅ rows in the COVERAGE Kruber section). When a COVERAGE row flips ✅, add its `weapon_key` to that table and it drops out next boot. The two `[Inventory Model Error]` ✅ rows (`we_2h_sword`, `we_1h_spears_shield`) ARE excluded (3P confirmed; the tag is a keep-preview caveat). `bw_1h_flail_flaming` is INCLUDED (🔧 in COVERAGE wins over the in-code `[Working]` label).
- **Suffix labels.** Each row title carries the current chosen set in brackets — e.g. "Elf Glaive rendered on Kruber body [Empire Greathammer]". The `[bracket]` refreshes on **menu re-open** (VMF caches the open label — `reference_vmf_checkbox_cached_display_state`), stated in the dropdown tooltip; the set itself applies live.
- **Live-apply + persist + boot-replay reuse the existing machinery verbatim.** Each dropdown registers a `kind="wield"` record into `_setting_index` (new `setting_id = wt_dev_anim_<port>_set`, still under the `^wt_dev_anim_` dispatch in `weapon_tweaker.lua:4565` — no main-file edit). `_apply_wield_change` writes `wield_anim_career_3p[career]` for EVERY Kruber career on the port, `_try_force_rewield` re-fires the stance immediately, `reapply_stored_picks` replays tuned picks at boot.
- **3P-only guarantee:** the chooser only ever writes `wield_anim_career_3p` (a 3P field). It never touches `anim_event` / `wield_anim` / `state_machine` (1P/universal). 1P is the shared `first_person_base` skeleton and is never modified (`feedback_cross_char_transforms_3p_only`).
- The per-attack picker code (`_build_port_group`, `kind="anim_event"` apply) is left **dead-but-present** so `/wt_dump_anim_picks` and `/wt_coverage` (which read live `Weapons.*`, not the widget tree) keep working unchanged.

## 0.12.137-dev (2026-06-21) — Passive charge restore for cross-character staves & Moonfire Bow

### Added (`wt_passive_charge_restore` toggle, default OFF) — `[untested]`
New per-frame feature that restores the passive overcharge-vent / energy-regen mechanic for two cross-character weapon families when wielded on a career that lacks it natively:

- **Sienna staves** (and any overcharge weapon): slowly **vent** overcharge. The native passive decay rate is read from `OverchargeData[career_name]` (`bulldozer_player.lua:206`), so a non-Sienna career stores `overcharge_value_decrease_rate = 0` and the staff never vents on its own. We drive `overcharge_ext:remove_charge(1.0 * dt)` each frame (rate `1.0` matches every Sienna staff career's native rate, `overcharge_data.lua:41/52/63`), gated only when there's overcharge to vent.
- **Moonfire Bow** (`we_deus_01`, any energy bow): slowly **regenerate** charge. The native regen rate is read from `EnergyData[career_name]` (`bulldozer_player.lua:207`), defined only for the four Kerillian careers (`energy_data.lua:4-27`, `recharge_rate = 1.5/s`); any other career falls back to `recharge_rate = 0` so the bow drains and never refills (bricks after ~8 shots). We drive `energy_ext:add_energy(1.5 * dt)` each frame, gated below max.

**Hard constraints honored:**
- **Consumption side only.** Uses `remove_charge` / `add_energy` (both clamp internally). Never mutates `_max_overcharge` / `max_value` / `_max_energy` (engine `NetworkConstants` cap → `fassert` crash; see `feedback_vt2_max_resource_consumption_side`).
- **Owner-authoritative networking.** Both extensions are simulated by the owning peer and broadcast via the game object (husks are read-only). The tick drives **only** `Managers.player:local_player().player_unit`, so the local human's value is corrected on the peer that owns it and replicated automatically — no double-apply, no remote/bot writes.
- **Cross-character only.** Gated on the LIVE native rate being `0`/absent (`overcharge_value_decrease_rate == 0` / `_recharge_rate == 0`-or-nil). Any career that natively vents/regens (every Sienna career, the four Kerillian careers, drakefire dwarves, etc.) is left entirely untouched.
- **nil/type-safe.** `ScriptUnit.has_extension` for every extension, wielded-weapon-may-be-absent guards, and the per-unit body + each engine call wrapped in `pcall` (Stingray `*.node`-class fatals bypass inner pcalls, so an outer net is present).

**Implementation:** new module `scripts/mods/weapon_tweaker/_wt_passive_charge.lua` exposing `M.tick(dt)`, called from the single existing `mod.update` in `weapon_tweaker_backend.lua` (no new `mod:hook`, so no duplicate-hook concern; `mod.update` now captures the VMF-supplied `dt`). Detection keys off the wielded item template: `overcharge_data` table present = overcharge weapon; an action of `kind == "bow_energy"`/`"aim_energy"` = energy bow.

## 0.12.132-dev (2026-06-19) — CRITICAL multiplayer fix: anim-event RPC feedback loop (every player's 3P stuck on endless repeat)

### Fixed (game-breaking, multiplayer)
A/B-confirmed: with wt enabled, in a 2+ human lobby **every** player's 3P animation was stuck on an endless repeat/loop, on **every** weapon. Disabling wt cleared it instantly.

**Root cause:** the `AnimationSystem.anim_event_with_variable_float` crash-guard hook (added v0.12.128, `weapon_tweaker.lua:2510`) **dropped vanilla's 6th parameter `skip_sync`**. The networked-anim RPC receiver (`rpc_anim_event_variable_float`, `animation_system.lua:312`) replays a received event with `skip_sync=true` precisely so it does **not** re-broadcast. With `skip_sync` omitted from the hook signature, `func(...)` was called with only 5 args → `skip_sync=nil` → vanilla's `if not skip_sync and Managers.state.network:game()` (`animation_system.lua:140`) re-sent the RPC. So **every husk that received a variable'd anim event re-broadcast it → infinite host↔client RPC feedback loop**, re-firing the animation every network tick. Only manifests in a network game with ≥2 humans (needs a peer to bounce the RPC with) — hence "only in a lobby with another player," all humans, every weapon, solo immune.

**Fix:** thread `skip_sync` through the hook signature and pass it to `func` unchanged, so husk replays stay local (`skip_sync=true`) as vanilla intends. The find-variable crash guard (the hook's original purpose — prevents the `es_bastard_sword`-charged-on-non-native `animation_set_variable(nil)` crash) is untouched.

> v0.12.128–v0.12.131 (the crash guard + its drop-vs-fire-bare tuning, from the memory-leak thread) shipped without CHANGELOG entries; this entry documents the regression they introduced and its fix.

## 0.12.127-dev (2026-06-19) — Anim confirmed: Saltzpyre Billhook on all Kruber careers

Flipped `unlock_es_{mercenary,huntsman,knight,questingknight}_wh_2h_billhook` to `[confirmed working]` (user-verified in-game). Per-receiver this time (Kruber only) — Kerillian receivers stay `[untested]`. See `TESTING_STATUS.md`.

## 0.12.126-dev (2026-06-19) — Forced-GC leak test on mission exit (lua_heap diagnosis)

INSTRUMENT ONLY. The host log already revealed the real mechanism via the existing per-state heap sampler: the Lua heap **ratchets up per mission** (≈150 MB keep baseline → 513 MB mission 1 → 311 MB after exit → 699 MB mission 2 — i.e. each mission loads ≈365 MB and ≈160 MB of it is NOT freed on exit). wt's own per-transition apply is only +6 KB, so it's not wt's direct allocation — it's that something during the mission isn't released. The one thing the live sampler couldn't answer (it deliberately never forces GC) is whether that un-freed heap is a true retained-reference **leak** or just collectable garbage. This adds a forced `collectgarbage("collect")` on `StateIngame/exit` that logs `reclaimed garbage` vs `survives GC` — if "survives GC" climbs each mission, it's a real leak to hunt; if it returns to baseline, it's GC pressure. Debug-gated (`enable_debug_logging`). Combine with 0.12.125's boot breakdown.

## 0.12.125-dev (2026-06-19) — Per-subsystem boot mem-probes (lua_heap-cap diagnosis)

INSTRUMENT ONLY (no behavior change) — to find what actually drives wt's Lua-heap footprint instead of guessing. Added ungated boot `[mem-probe]` lines that print the lua delta of each heavy subsystem on one boot:
- `wt weapon_backend: +X MB` — the backend dofile, which the existing `boot_lua` total never counted (baseline is set *after* it).
- `wt_dev_anim catalog+vocab: +X MB (N entries)` — the dev anim picker's dynamic catalog + skeleton vocab, built at boot (`_ensure_catalog_built`).
- `wt_dev_anim widget_tree: +X MB (N char groups)` — the per-pair dropdown tree VMF holds.
- `wt_dev_anim loc_keys: +X MB (N strings)` — the option-text loc strings (two per vocab value per entry).

All `[picker-only]` subsystems are resident at boot for every player even if they never open the picker — the suspected baseline-raiser that leaves less headroom for the per-mission force-load spike. Boot once with the log open; the breakdown tells us exactly where the heap goes, then we cut it.

## 0.12.124-dev (2026-06-19) — Animation test-status labels in the weapon availability menu

Prefixed the cross-character weapon entries in the availability menu with `[untested]` (the 3P-animation testing surface) and `[confirmed working]` for verified weapons, so we can track what's animation-ready for release. Same-character entries (native skeleton — animations work by default) are left unlabeled, as are group headers. 633 cross-character entries labeled `[untested]`; **Kerillian: Spear** (`we_spear`) and **Saltzpyre: Axe** (`wh_1h_axe`) marked `[confirmed working]` across all receivers (15 entries). See `TESTING_STATUS.md`.

## 0.12.123-dev (2026-06-19) — Warrior Priest punch buff (Reckoner Greathammer special): 3x stagger, 2x damage

### Added
- **`wt_priest_punch_buff`** (Weapon Overrides group, default OFF) — triples the stagger and doubles the damage of the Warrior Priest 2h hammer's **special attack**, the punch (`attack_slam`, reached via the weapon's push-stagger special). The punch action on `Weapons.two_handed_hammer_priest_template` vanilla-points at the shared `light_blunt_smiter_stab` damage profile; since that profile is shared with other weapons, we register a **private cloned profile** `wt_priest_punch_buffed` with the punch's damage (`power_distribution.attack ×2`) and stagger (`power_distribution.impact ×3`) scaled on its `default_target` + `targets`, then repoint only the punch action's `damage_profile` at it while the toggle is on (restoring the original key when off).
  - Profile is registered into `NetworkLookup.damage_profiles` **unconditionally at load** (same determinism rule as `wt_authentic_pistol`, PROJECT_STANDARDS §9.3) so a host with the toggle on and a client with it off don't diverge on the network index. Only the action repoint is gated.
  - Regression: `wt_priest_punch_buff_wired` (profile registered + in NetworkLookup + default_target scaled 2×/3×).

## 0.12.120-dev (2026-06-17) — Crash fix: universal attachment-node guard (Skullsplitter + tome on Kruber); remove Kruber Longbow zoom toggles

### Crash fix — `j_rightweaponcomponent11` engine-fatal on equip
Reported 2026-06-17 (GUID 459bd95e): equipping **Skullsplitter + a tome on Kruber Mercenary** hard-crashed the hero-view weapon preview with `[Script Error] j_rightweaponcomponent11`. Root cause: `GearUtils.link_units` runs `Unit.node(source, link.source)` per attachment link (`gear_utils.lua:293-308`), and `Unit.node` is **engine-fatal on a missing node** (bypasses pcall). The tome sub-unit's linking maps its `j_page_nr*` nodes onto `j_rightweaponcomponent11-14`, which Kruber's body lacks in this cross-character context. The existing per-spawn guard (`_wt_validate_attachment_sources`) only covers the weapon's own `.third_person` linking; a sub-attachment carries its **own** flat linking table that never passes through that hook (confirmed via the two distinct table addresses in the crash locals).
- **Fix:** new hook on `GearUtils.link_units` (the universal choke point — `GearUtils.link` calls it via the table) that **drops any link whose source/target node is absent** before the engine reads it. Purely subtractive — valid links (nodes present) are untouched, so it can't regress visibility (unlike the v0.12.112/.113 global-mutation bug that broke elf bows). Catches preview **and** in-mission, for every weapon/sub-attachment. `WT_LINK_UNITS_NODE_GUARD_MARKER`.
- Filter logic factored into a pure, engine-free `mod._wt_link_filter` with a new `/wt_regression_test` check **`link_units_node_guard`** (drops missing-node links, keeps present ones, zero-copy on the all-present path).

### Removed — Kruber Longbow zoom toggles
Removed the `kruber_longbow_disable_zoom` / `kruber_longbow_manual_zoom` settings and the `_patch_kruber_longbow_zoom` patcher (lua + `_data` + `_localization`). The Kruber Longbow keeps vanilla zoom behavior. (The unrelated longbow **3P model swap** for cross-character is untouched.)

## 0.12.119-dev (2026-06-11) — Flaming Flail wield redirect (fixes broken wield stance on non-Sienna); /wt_coverage skeleton probe

### Why
Two items off the new ANIMATION_COVERAGE.md walk list that don't need an in-game tuning session:
- **Flaming Flail (bw_1h_flail_flaming) on non-Sienna receivers** had a broken wield stance — the H2 attack redirect existed but the wield event didn't (the exact gap DECISIONS:36 flagged as needs-fix). 🧊 on both the Kruber and Kerillian rows.
- No in-game probe existed to bulk-answer "which of this character's ports have authored 3P events?" — deriving coverage was a manual `/animlog` + `/dump_actions` + eyeball walk per port.

### Changed
- **`weapon_tweaker.lua` (`_career_anim_redirect`):** `to_1h_flail_flaming → to_1h_flail` for non-`bw_` careers (Sienna keeps her native event; `wh_priest` override → `to_1h_hammer`, consistent with the table's other entries). `to_1h_flail` is the universal Empire-flail wield already proven on every character via es_1h_flail. **Needs in-game verify** — flipped to 🔧 in ANIMATION_COVERAGE.md.
- **`wt_dev_anim_picker.lua`: new `/wt_coverage` command** (PROJECT_STANDARDS §3.7 data harness): for the CURRENT character, walks every catalog port and reports wield + per-action `anim_event_3p` authored-ness against the live 3P skeleton — one parseable `[wt:coverage]` line per port, FULL/PARTIAL/NONE summary. One command per character refreshes the coverage matrix statuses. (Authored ≠ visibly plays in chain states — final word stays with the eye.)

## 0.12.118-dev (2026-06-11) — Anim picker: tuned picks now survive restart (boot re-apply); two display-name mislabels fixed

### Why
The user's animation workflow is: tune a port's 3P picks in the dev Anim Picker menu in-game, verify by eye, then have the values baked into source. The structural hole (2026-06-11 system audit): picks applied live via `on_setting_changed` and persisted in the VMF store, but **nothing replayed them onto `Weapons.*` at boot** — every tuned port silently reverted to patcher/template defaults on restart until baked. That made the picker a one-session scratchpad instead of the intended tune→persist→export→bake loop.

### Changed (`wt_dev_anim_picker.lua`)
- **`M.reapply_stored_picks()`** — called from `M.install()` (end of main wt.lua, AFTER all template patchers): walks `_setting_index` and re-applies every stored pick onto the live templates via the same `_apply_wield_change`/`_apply_anim_event_change` paths as a live menu change. Logs an ungated one-line summary (`N stored pick(s) applied`) so the user can confirm their tuning is live without Debug Logging.
- **Only user-CHANGED settings re-apply.** Each `_setting_index` rec now captures its build-time `default_value`; a stored value equal to it is skipped. Load-bearing guard: widget defaults are captured at `_data.lua` time (BEFORE the main-file template patchers run), so blindly re-applying everything would overwrite patcher output with stale pre-patcher state — exactly the brace/longbow/repeating-pistol ports.
- **Display-name mislabel fixes** (`_WEAPON_NAME`): `we_deus_01` = **Moonfire Bow** (was "Deus Greatsword") and `we_life_staff` = **Deepwood Staff** (was "Moonfire Bow"). The per-character `*_deus_01` keys are the CW weapons; the old labels would have routed tuning decisions at the wrong weapon.

### Notes
- The tuned values remain session-layer until exported (`/wt_dump_anim_picks`, paste-ready `_WIELD_3P`/`_ANIM_REMAP_3P` blocks) and baked into the patcher tables — boot re-apply makes the interim state survive restarts, it does not replace baking.

## 0.12.117-dev (2026-06-08) — BR true-flight extra-shot gating matches vanilla; regression harness gets a skip channel (Issue #74)

### Why
Issue #74 follow-through from the 2026-06-08 re-review:
- The BR true-flight `fire` reimpl gated `set_shooting()` / ammo / overcharge / energy on `self.extra_buff_shot`, which is only ever assigned `false` — so under extra-shot buffs (Waywatcher +projectile talent, extra-shot procs) the free extra projectiles also bumped spread state and charged ammo/overcharge where vanilla skips them.
- `/wt_regression_test` counted `"skip: ..."` returns as FAIL, polluting the failure count whenever game tables weren't loaded yet.

### Changed
- **`weapon_tweaker_big_rebalance.lua`:** new file-scope `mod._wt_tf_is_extra_shot(i, num_projectiles, num_extra_shots)` implementing vanilla's per-projectile test exactly (`extra_shots_idx = num_projectiles - num_extra_shots + 1; is_extra_shot = extra_shots_idx <= i`, action_true_flight_bow.lua:128,132). All four gates (set_shooting / ammo / overcharge / energy) now key off it. Also tidied the mangled-but-equivalent `shot_count_offset` ternary to vanilla's form (action_true_flight_bow.lua:137).
- **`weapon_tweaker.lua`:** `/wt_regression_test` runner gained a SKIP channel — `"skip: <reason>"` returns are echoed and counted separately, no longer FAIL. Summary line now reports passed/failed/skipped.

### Tests
- `wt_br_trueflight_extra_shot_gating_matches_vanilla` — pins vanilla's truth table (0 extras → none flagged; 5 projectiles / 2 extras → exactly i=4,5 flagged; nil extras behaves as 0).

## 0.12.116-dev (2026-06-08) — Fix BR true-flight speed falloff sign-flip (projectiles 2+ fired backwards)

### Why
Post-ship re-review of the v0.12.115 audit fixes (fresh-eyes verification pass, 2026-06-08) found a pre-existing bug two lines below the audited `extra_buff_shot` gate in the BR true-flight `fire` reimpl: the per-projectile speed falloff was the **sign-flip** of vanilla — `speed = speed * (i * 0.05 - 1)` instead of vanilla's `speed = speed * (1 - i * 0.05)` (`action_true_flight_bow.lua:152`). For every projectile after the first (i ≥ 2) the multiplier is negative (i=2 → −0.9×), so with `br_hook_trueflight_fire` enabled, multi-projectile fires (Waywatcher extra-projectile talent, extra-shot buffs) launched projectiles 2+ **backwards at negative speed**. Present since the reimpl landed (~28 versions).

### Changed
- **`weapon_tweaker_big_rebalance.lua`:** falloff factored into `mod._wt_tf_projectile_speed(speed, i)` (file scope, NOT inside the master-gated hook installer, so it exists even with BR off) implementing vanilla's formula; the fire loop now calls it.

### Tests
- `wt_br_trueflight_speed_falloff_matches_vanilla` — asserts i=1 passes through unmodified, i=2 matches vanilla's 0.9× exactly, and i=2..5 all stay positive (the sign-flip made them negative).

## 0.12.115-dev (2026-06-07) — Audit fixes: brace damage-profile peer-index divergence, bot loadout arg, true-flight dead branch, dead loc keys

### Why
Repo-wide audit (2026-06-07). (Note: the CHANGELOG had drifted — MOD_VERSION was at 0.12.114-dev with no entries since 0.12.95-dev; this entry brings the head current. The .96–.114 gap is pre-existing and out of scope.)

### Changed
- **`weapon_tweaker.lua` ~2807 (HIGH, MP):** the `wt_authentic_pistol` custom damage profile was registered into `NetworkLookup.damage_profiles` only inside the toggle-gated `_apply_authentic_brace_mode()`. Per `PROJECT_STANDARDS §9.3` (gated-registration divergence), a host with the authentic-brace toggle ON and a client with it OFF get **different network indices** for that profile → `NetworkLookup` strict `__index` crash ("Table damage_profiles does not contain key") or silent wrong-damage decode when a networked brace shot resolves on the other peer. Now registers the profile **unconditionally at load** (`_wt_clone_shot_sniper_no_dropoff()` is idempotent; same load timing); only the template patching stays toggle-gated. **Residual:** full cross-*mod-set* determinism (peer also runs CWV/other NetworkLookup appenders vs not) still needs routing through bt's shared sorted registry — tracked as a follow-up.
- **`weapon_tweaker_backend.lua` ~170 (MEDIUM):** the `get_loadout_item_id` hook dropped vanilla's 4th `is_bot` arg (`backend_interface_item_playfab.lua:512`) on both fall-through calls, so bot loadout lookups silently used the player-default path. Now threads `is_bot` through and only answers the modded cache for the local player (`not is_bot`); bot queries fall through to vanilla.
- **`weapon_tweaker_big_rebalance.lua` ~2503/2529 (LOW):** the BR `ActionTrueFlightBow.fire` reimpl declared an `add_spread` 2nd param that vanilla never passes (`action_true_flight_bow.lua:121` is `fire(self, current_action)`), so its `if add_spread then spread_extension:set_shooting() end` branch was dead — spread "shooting" state was never set on true-flight fires. Dropped the vestigial param; gate on the reimpl's own `not self.extra_buff_shot` to match vanilla (`action_true_flight_bow.lua:143`).
- **`weapon_tweaker_localization.lua` ~1064 (cleanup):** removed 6 orphan loc strings for long-deleted settings (`enable_weapon_unlocks_core`, `enable_weapon_runtime_guards`, `enable_weapon_wield_slot_guard`, `enable_weapon_create_equipment_guard`, `enable_weapon_career_action_injection`, `force_bretonnian_shield_unlock`) flagged by `qa/check_name_integrity.ps1`.
- MOD_VERSION → 0.12.115-dev.

### Tests
- `wt_authentic_pistol_profile_registered_unconditionally` (`/wt_regression_test`) — asserts `wt_authentic_pistol` is in `DamageProfileTemplates` + `NetworkLookup.damage_profiles` regardless of the toggle. Fails if the registration is ever re-gated.
- `is_bot` passthrough and the true-flight gate are not cleanly keep-testable (need a live bot loadout / the BR true-flight path) — verify in-game per below.

### To verify
- **MP (needs 2 clients):** host with authentic-brace ON, client with it OFF, fire the brace at an enemy near the client — no `damage_profiles` crash and damage is correct. This is the load-bearing one; **do not promote until 2-client verified.**
- Bots: equip a modded weapon, check a bot's loadout resolves to its own gear (not your modded weapon).

## v0.12.95-dev — 2026-05-26

- **REMOVED**: Saltzpyre's crossbow as a toggle for the 4 Kruber careers. Ceded ownership to `character_weapon_variants` v0.1.347-dev's `cwv_es_crossbow` variant (default-on). The polish items it carried (3P grip offsets vs rifle anims, smoke FX on shot, missing bolt in 3P) made it too heavyweight for wt's "simple toggle" model.
- Strips the `_patch_crossbow_template_for_kruber` base template patcher (`wield_anim_career_3p[es_*] = "to_handgun"`), the `_build_crossbow_kruber_safe_third_person` lazy builder, and the `_wt_crossbow_kruber_attach_safe_apply` preview-time attachment-node substitution — all migrated to CWV.
- Bardin's wh_crossbow toggles (default-off) are unchanged; Saltzpyre's native wh_crossbow access is unchanged.

## 0.12.89-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("Weapon Tweaker v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `weapon_tweaker.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[wt] v<MOD_VERSION> loaded")` runs once.

## 0.12.88-dev (2026-05-25) -- Sprinkle `_dbg` instrumentation at anim-remap dispatch / template patchers / BR function hooks (sampled on hot paths)

### Why
User enabled `enable_debug_logging` and played; log captured almost nothing for wt because the load-bearing event points (template patchers, anim-remap REMAP/FORCE/REDIR branches, BR function hooks) had no `_dbg` calls. Dummy-static-bug triage needs visibility into whether wt's animation_event hook is firing at all, whether the cross-character REMAP path is being hit, and whether the BR function hooks (Flamethrower / Beam / TrueFlight) are taking the modded path or vanilla.

### Changed
- `weapon_tweaker.lua`:
  - **`Unit.animation_event` hook (line ~1159)** -- added file-local `_anim_event_call_count` sample counter (`_ANIM_EVENT_SAMPLE_N = 60`) and a `_dbg("[wt:anim] event=enter ...")` at the top of the body that fires 1-in-60 calls. PER-FRAME hot path -- sampling is mandatory.
  - **REMAP branch inside the same hook** -- added `_anim_event_remap_count` (separate counter, `_ANIM_EVENT_SAMPLE_REMAP_N = 30`) + `_dbg("[wt:anim] event=REMAP src=... -> tgt=... career=... tmpl=... key=... sample=N")` so cross-character anim REMAP hits are visible without flood.
  - **`_patch_brace_template_for_kruber` / `_patch_longbow_empire_template_for_saltzpyre` / `_patch_longbow_template_1_for_saltzpyre` / `_patch_repeating_pistol_template_1_for_kruber`** -- added `_dbg("[wt:tpl_patch] event=applied template=<name> career_overrides=N action_remaps=M")` exit lines + a `_dbg_alert` on the missing-template skip path. Boot-time only; always-on.
- `weapon_tweaker_big_rebalance.lua`:
  - Added local `_dbg` helper at the top (file-local mirroring of the main file's helper since Lua 5.1 file-locals don't cross dofile boundaries).
  - **`BR.apply_all` entry + exit** -- `[wt:br_hooks] event=apply_all_begin master_active=...` / `event=apply_all_done hooks_installed=...`. Boot-time only; always-on.
  - **`_install_function_hooks`** -- added `[wt:br_hooks] event=install_begin` / `event=install_done flamethrower=... beam=... trueflight=...` markers; `event=skip_install reason=master_off` on the bt master-off short-circuit.
  - **Flamethrower `_select_targets`, Beam `client_owner_post_update`, TrueFlight `client_owner_start_action` + `fire`** -- each got its own sample counter (`_BR_HOOK_SAMPLE_N = 60`) and a `_dbg("[wt:br_hooks] event=<hook_name> sample=N ...")` line. Beam is per-frame while held; sampling is mandatory. Flamethrower/TrueFlight are per-fire but sampled for consistency.

### Existing instrumentation left unchanged (verified still present + correct)
- **`SimpleInventoryExtension.wield` (Layer 3 `traced_hook` at line ~1474)** -- emits paired `[wt:trace] event=enter|exit class=SimpleInventoryExtension method=wield` lines (gated on debug_logging) PLUS the existing `[wield] slot=... career=... key=... template=... anim_event_3p=... wield_anim_3p=...` line at line ~1526.
- **`SimpleHuskInventoryExtension.wield` (`safe_hook` at line ~1548)** -- no extra trace needed; husk wield is a pass-through whose state-population side effect is captured by `_populate_unit_state_from_wield`.
- **`GearUtils.create_equipment` (Layer 3 `traced_hook` at line ~1730)** -- emits paired enter/exit trace lines under debug_logging. Existing `[create_equipment] pre-resolved item_units` log line preserved.
- **`GearUtils.spawn_inventory_unit` (Layer 3 `traced_hook` at line ~2883)** -- the cross-character 3P swap dispatch; emits paired enter/exit trace lines. The downstream swap helpers (`_wt_brace_3p_swap_apply`, `_wt_longbow_3p_swap_apply`, `_wt_repeating_pistol_3p_swap_apply`) each already log `[wt brace-3p-swap]` / `[wt sp-longbow-crossbow]` / `[wt rp-pistol-handgun]` enter/SKIP/swap lines on every path -- well-instrumented, left as-is.
- **`MenuWorldPreviewer.equip_item` post-hook (line ~3465)** -- preview swap helpers each emit `[wt brace-3p-swap preview]` / `[wt sp-longbow-crossbow preview]` / `[wt rp-pistol-handgun preview]` lines on success. Already-instrumented.

### What I deliberately skipped
- **`mod.update` / per-frame update consumer bodies** -- none in wt's hot path that would benefit; per the brief.
- **Inner per-action / per-sub_action loops inside the template patchers** -- count+rollup is enough; per-iteration would emit dozens of lines per template at boot.
- **`Unit.animation_event` REDIR / FORCE / SUFFIX branches** -- the existing `_log_anims` (`/animlog` command) chat-echo path already covers per-event detail; adding a second sampled-debug stream would duplicate. The REMAP branch is the highest-suspect for cross-character bugs, so it's the one branch that got a dedicated sample counter.
- **`Unit.animation_event` per-call** without sampling -- would flood the log; 1-in-60 covers "is the hook even firing?" diagnostics.
- **Damage-path hooks on `DamageUtils.*` / `ActionAttack.*`** -- wt has no direct hooks on these classes (verified via Grep). Only the BR function hooks (Flamethrower / Beam / TrueFlight) interact with the damage pipeline, and those got their own `[wt:br_hooks]` markers.
- **`_safe_hook.lua` body** -- already has Layer 3 traced_hook which emits `[wt:trace] event=enter|exit class=... method=... n_args=... / n_returned=...` on every fire. Adding additional `_dbg` inside the wrapper would double-emit.

### Build
`VMBLauncher.exe build weapon_tweaker` -- verification only. NOT deployed, NOT uploaded (user-explicit doctrine 2026-05-25 EOD: develop, test, then user approves per-build for ship).

## 0.12.87-dev (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[wt] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- weapon_tweaker.lua -- removed the load-time `mod:echo("weapon_tweaker v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[wt] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("weapon_tweaker v%s loaded", MOD_VERSION)` retained for log-side visibility.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build weapon_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.12.86-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- weapon_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- weapon_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build weapon_tweaker -- verification only. NOT deployed, NOT uploaded.

## v0.12.85-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[wt] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load — self-documenting console_logs. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. ALWAYS fires (not gated on debug_logging). Additive to the existing "Weapon Tweaker: Baseline Active" operational line further down — does not replace it.

### Changed
- `weapon_tweaker.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[wt] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.12.85-dev.

### Notes
- Fingerprint walks the post-CIM-strip widget tree on the local peer — surfaces what settings are actually live, not just the canonical definition.

## v0.12.84-dev — Layer 3 traced_hook helper: structured entry/exit log lines gated on debug logging

### Why
User idea: "Wrap every part of the code in a logger that shows us that it fired" when debug mode is on. Targeted form: wrap every `mod:hook` body with `[wt:trace] event=fire class=GearUtils method=spawn_inventory_unit n_args=N` at entry and `[returned n_vals=M]` at exit. Catches "did the hook fire?" and "did it return what we expected?" — exactly the v0.12.77/.78/.79 safe_hook bug class.

Layered on top of the existing wt safe_hook helpers:
- Layer 1 (existing): `mod:hook` — vanilla VMF (chain dispatch, no isolation).
- Layer 2 (v0.12.77+): `mod:safe_hook` — pcall-isolated + multi-return-safe wrap.
- Layer 3 (NEW): `mod:traced_hook` — Layer 2 PLUS structured entry/exit log lines gated on `enable_debug_logging`.

A consumer adopts `mod:traced_hook` when they want fire-confirmation + return-shape visibility. Otherwise stays on `mod:safe_hook`.

### Added
- `_safe_hook.lua` — `mod.traced_hook(self, class, method, handler)` and `mod.traced_hook_safe(self, class, method, handler)` methods. Both delegate to safe_hook / safe_hook_safe (Layer 2) for pcall isolation + multi-return preservation — do NOT re-implement either. Layer the trace lines on top by wrapping the user handler in a tracing closure.
  - Trace format: `[wt:trace] event=enter class=<C> method=<m> n_args=N` and `[wt:trace] event=exit  class=<C> method=<m> n_returned=M`.
  - Gate: `mod:get("enable_debug_logging")`. Toggle off => no trace lines, semantically identical to safe_hook.
  - Layer 3 marker constant `CT_WT_TRACED_HOOK_MARKER_v0_12_84 = "wt-traced-hook-layer3-installed"` for the new regression test.
- New `/wt_regression_test` check `wt_traced_hook_present` (next to the existing `wt_safe_hook_installed` block at ~L4357):
  - Asserts marker constant present.
  - Asserts `mod.traced_hook` and `mod.traced_hook_safe` are callable.
  - Smoke-tests installation + invocation on a fresh dummy class with toggle OFF then toggle ON. Asserts no crash and that the 3-return / 1-nil-hole shape survives the wrapper in both modes. Restores prior toggle state on exit.

### Migrated
Three load-bearing safe_hook call sites flipped to traced_hook. These fire on weapon wield / equip events (NOT per-frame), so trace lines are flood-safe.

- `weapon_tweaker.lua` L1414 — `mod:safe_hook("SimpleInventoryExtension", "wield", ...)` → `mod:traced_hook(...)`. Local-player wield. Confirms the wield hook fires per slot swap.
- `weapon_tweaker.lua` L1666 — `mod:safe_hook("GearUtils", "create_equipment", ...)` → `mod:traced_hook(...)`. In-game (path 1 of 3) weapon rendering. Per-mission-spawn / per-keep-load rate.
- `weapon_tweaker.lua` L2813 — `mod:safe_hook("GearUtils", "spawn_inventory_unit", ...)` → `mod:traced_hook(...)`. Cross-character 3P swap dispatch. The canonical 5-return / 2-nil-hole function that motivated the safe_hook fix cycle. Trace shows n_args + n_returned per fire — debugging swap regressions gets concrete return-count visibility for the first time.

### Rate-limit caveat
Per-frame hooks (e.g. `mod.update`) MUST NOT be wrapped in `traced_hook` — at 60+ fires/sec they would flood the log when the toggle is on. The three migrated sites are all event-rate. wt has no per-frame hook adoption today; if/when it does, leave it on `safe_hook` and document the rate-limit reason inline.

### Files changed
- `weapon_tweaker/scripts/mods/weapon_tweaker/_safe_hook.lua` — added Layer 3 header subsection + `mod.traced_hook` / `mod.traced_hook_safe` methods + `CT_WT_TRACED_HOOK_MARKER_v0_12_84` constant.
- `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua` — MOD_VERSION bump; 3 hook sites migrated; new `_rt_register("wt_traced_hook_present", ...)` block.
- `weapon_tweaker/itemV2.cfg` — title + description bumped to v0.12.84-dev.
- `VMF_RECIPES.md § 2b` — extended with Layer 3 traced_hook sub-section + rate-limit caveat.
- `PROJECT_STANDARDS.md § 3.6` — one-line cross-ref to traced_hook (Layer 3) added.

### Verification
1. Restart VT2, load keep.
2. `/wt_regression_test` — new check `wt_traced_hook_present` should PASS. Existing `wt_safe_hook_installed` + `wt_safe_hook_preserves_multi_returns_with_nil_holes` checks must continue to PASS (Layer 3 stacks on top of Layer 2; it does not replace it).
3. Toggle `Debug Logging` ON in the VMF mod menu, wield a weapon and equip another — expect to see paired `[wt:trace] event=enter|exit class=SimpleInventoryExtension method=wield n_args=...` / `n_returned=...` lines plus matching pairs for `GearUtils.create_equipment` and `GearUtils.spawn_inventory_unit` in `%APPDATA%\Fatshark\Vermintide 2\console_logs\`.
4. Toggle Debug Logging OFF — no `[wt:trace]` lines should emit.

### Sample log lines (toggle on)
```
[wt:trace] event=enter class=GearUtils method=spawn_inventory_unit n_args=12
[wt:trace] event=exit  class=GearUtils method=spawn_inventory_unit n_returned=4
```

## 0.12.83-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `weapon_tweaker.lua` — installed `_dbg_alert` helper alongside existing `_dbg`. Added `_rt_register("dbg_helpers_two_channel", ...)` alongside the existing seven wt regression checks.
- `weapon_tweaker.lua` ~L3152 — promoted ONE `_dbg(...)` call site to `_dbg_alert(...)`: the `[wt sp-longbow-crossbow] SKIP (pcall returned nil — internal abort, see prior warning)` line. This branch only fires after the preceding `mod:warning("[wt sp-longbow-crossbow] pcall ERROR ...")` has already logged, so the follow-up SKIP is part of the alert chain. With the toggle on, the user will see both messages in chat.
- `itemV2.cfg` — bumped to v0.12.83-dev.

### Notes
- 35 existing `_dbg(...)` call sites audited. 34 kept as `_dbg` (state/scale/wield/transition confirmations, plus expected SKIP branches like "career not Kruber" / "hand=right, not left" / "vanilla v_w3p was nil" — all are normal guard paths, not error conditions). 1 promoted to `_dbg_alert` (the post-pcall-failure SKIP at L3152).
- 0 bare `mod:echo` reclassified — all `mod:echo` calls are inside `/wt_*` / `/verify_*` chat command bodies (user-operational) or are permanent operational output (load banner).

### Notes on judgment calls
- SKIP branches like `[wt brace-3p-swap] SKIP (career not Kruber: %s)` and `(vanilla v_w3p was nil)` use the alert word "nil" but represent expected-skip paths where the guard is intentional. Per the policy's "Ambiguous → leave as `_dbg`. Conservative default."
- `[wt sp-longbow-crossbow] SKIP (crossbow 3P package not loaded)` similarly — package-not-loaded is an expected timing condition, not an error.

## 0.12.82-dev (2026-05-25) — Finish §3.6 rename: migrate stale `mod:get("wt_debug_mode")` gate call sites

### Why
v0.12.81-dev renamed the widget from `wt_debug_mode` to `enable_debug_logging` in `weapon_tweaker_data.lua` + `_localization.lua`, but four `mod:get("wt_debug_mode")` call sites in `weapon_tweaker.lua` (the `_dbg` helper at L118, the `D = mod:get(...)` cached wield-hook gate at L1442, the loadout-dump gate at L3782, plus comments) were not updated in the same pass. Result: the widget wrote `enable_debug_logging` while the gate read `wt_debug_mode` — debug mode was de-facto non-functional. `tools/mod-lint/lint-mod.ps1` doesn't catch a stale `mod:get` against a removed widget, so this slipped through.

### Fixed
- `weapon_tweaker.lua` — all four call sites now read `mod:get("enable_debug_logging")`. The legacy-key migration logic at L132-145 deliberately keeps a `mod:get("wt_debug_mode")` (with a `legacy_wtdebug` local) so an early-adopter's pre-rename clicked-on value still gets carried over.

### Note
The `mod:echo("Weapon Tweaker v" .. MOD_VERSION)` at line 97 still fires unconditionally — wt is on the `-dev` track, so the user-policy "no chat-echo unless `enable_debug_logging`" only applies to stable releases. The echo gets gated automatically the day wt drops the `-dev` suffix.

## 0.12.81-dev (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). wt previously had `wt_debug_mode` nested inside `diagnostics_group` — renamed and un-nested.

### Changed
- `weapon_tweaker_data.lua` — removed `diagnostics_group` wrapper; `wt_debug_mode` renamed to `enable_debug_logging` at top-level bottom of `options.widgets`.
- `weapon_tweaker_localization.lua` — removed `diagnostics_group` / `wt_debug_mode` / `wt_debug_mode_description`; added `enable_debug_logging` + `enable_debug_logging_tooltip` per the standard.
- `weapon_tweaker.lua`:
  - `_dbg(fmt, ...)` helper now reads `mod:get("enable_debug_logging")` (was `wt_debug_mode`). Output prefix `[wt:dbg]` unchanged.
  - All other `mod:get("wt_debug_mode")` call sites (wield hook cached lookup, `_dbg_dump_local_player_loadout`) renamed to `enable_debug_logging`.
  - `_migrate_legacy_debug_setting()` now ALSO carries the saved value of `wt_debug_mode` (in addition to the v0.12.74 legacy `debug` / `enable_weapon_debug_logging` keys) into the new `enable_debug_logging` key on first load. Sentinel `wt_debug_migration_v1` continues to gate it to one-time.
- `itemV2.cfg` — title + description bumped to v0.12.82-dev.

### Notes
- **Migration**: existing users with `wt_debug_mode = true` get auto-carried into `enable_debug_logging = true` on first load via the migration helper.

## 0.12.81-dev (2026-05-25) — Tighten localization strings to vanilla style (15 entries rewritten)

### Why

Mod-menu descriptions in `weapon_tweaker_localization.lua` drifted into multi-paragraph essays for `authentic_brace_of_pistols`, the Moonfire Bow toggles, the Kruber Longbow zoom pair, and the Big Rebalance master/meta-init tooltips. Vanilla VT2 tooltips are uniformly terse. This pass aligns wt's heavy hitters with the vanilla voice per the new `LOCALIZATION_STANDARD.md` § 11 rules.

### Changed

- `authentic_brace_of_pistols_description`: 838 → 305 chars; kept all 5 mechanical bullets (handgun shot, single-shot, no manual reload, ammo cap, spread) + "Requires restart" but dropped the flavor commentary ("Flintlocks weren't tack-drivers...").
- `wt_debug_mode_description`: 565 → 220 chars; kept the `[wt:dbg]` tag enumeration + "off = warnings only" but dropped per-event prose.
- `moonfire_aoe_revert_description`, `moonfire_cosmetic_puff_description`: trimmed; kept 1.5m / 0.75m magnitudes and the "override" relationship between the two toggles.
- `kruber_longbow_disable_zoom_description`, `kruber_longbow_manual_zoom_description`: dropped state-machine internals ("zoom_in stage, ~0.01s delay") that don't help the player.
- `br_master_description`, `br_misc_weapons_meta_init_description`, `br_hook_shield_slam_description`, `br_shield_slam_replace_description`, `br_misc_status_dodge_count_description`, `br_misc_chaos_raider_special_staggers_description`: trimmed "subscribe to it separately, then restart the game" prose, kept the bt-master gate.
- `weapon_traits_description`, `cw_melee_traits_description`, `cw_ranged_traits_description`: trimmed.

### Not touched

- The vanilla trait descriptions (`trait_melee_*_description`, `trait_ranged_*_description`, `cw_trait_*_description`) are already vanilla-style (Critical hits grant +20%% attack speed for 5 seconds.) — left as canon.
- Per-BR-toggle short labels (`br_1h_hammer_*`, `br_2h_sword_*`, etc.) — already ≤6 words.

### Build

VMBLauncher.exe build weapon_tweaker — verification only.

## 0.12.80-dev (2026-05-25) — Hardening: regression test fixture for safe_hook multi-return + nil-hole preservation

### Why
v0.12.79's CHANGELOG closed with "Worth adding a regression test that asserts safe_hook'd functions preserve all positional returns INCLUDING nil values." This release adds that test as a hard fixture under `/wt_regression_test`.

The existing `wt_safe_hook_installed` check (kept) only validates the module loaded and the methods are callable — it does NOT exercise the actual multi-return path that broke silently across v0.12.77/.78/.79. The new check builds a fresh dummy class per invocation, wraps a 5-return / 2-nil-hole method via `mod:safe_hook`, and asserts positional integrity through the wrapper.

### Added
- New `/wt_regression_test` check `wt_safe_hook_preserves_multi_returns_with_nil_holes` (next to `wt_safe_hook_installed`, not replacing it):
  - Builds a dummy class on every invocation with `method = function(self, ...) return 1, nil, 2, nil, 3 end` (mimics melee-weapon `GearUtils.spawn_inventory_unit`'s nil-hole shape, more aggressive — 5 returns, 2 nils).
  - Fresh table identity per run guarantees VMF's duplicate-hook guard never trips, so the test is rerunnable any number of times in one session.
  - Wraps the method via `mod:safe_hook(_dummy_class, "method", function(func, ...) return func(...) end)`.
  - Captures the call result via `select("#", ...)` + table-pack idiom and asserts `n == 5` plus each positional slot exact-value (catches both v0.12.77 single-return collapse AND v0.12.78 non-deterministic `#table` truncation).
  - Returns self-diagnosing failure strings (e.g. `safe_hook truncated multi-return: got n=2 expected 5 (results=1,nil,...)`).
  - Also covers the error path: safe-hooks a `raiser` method that raises and asserts safe_hook itself didn't blow up with its own internal error (vs. the expected `test-raise` propagating from vanilla fall-through).
- New version constant `MOD_VERSION = "0.12.80-dev"` (was `0.12.79-dev`).

### Files changed
- `scripts/mods/weapon_tweaker/weapon_tweaker.lua` — `MOD_VERSION` bump; new `_rt_register("wt_safe_hook_preserves_multi_returns_with_nil_holes", ...)` block appended next to the existing `wt_safe_hook_installed` block (~L4226).
- `itemV2.cfg` — title + description bumped to v0.12.80-dev.

### Verification
1. Restart VT2, load keep.
2. `/wt_regression_test` — new check `wt_safe_hook_preserves_multi_returns_with_nil_holes` should PASS.
3. To prove the test would catch the bug: temporarily revert `_safe_hook.lua`'s `unpack(results, 2, n)` back to `unpack(results, 2)` and re-run — the check fails with a diagnostic message naming the truncated count.

## 0.12.79-dev (2026-05-25) — CRITICAL FIX #2: `unpack(results, 2)` non-deterministic with nil holes

### Why
v0.12.78's fix replaced `local ok, result_or_err = xpcall(...)` with `local results = { xpcall(...) }; return unpack(results, 2)`. That preserved trailing returns BUT introduced a subtler bug: `unpack(results, 2)` without an explicit `j` argument defaults to `j = #results`.

In Lua 5.1, `#table` is **undefined behavior for arrays with nil holes**. `GearUtils.spawn_inventory_unit` returns 4 values (`weapon_3p, ammo_3p, weapon_1p, ammo_1p`) — `ammo_3p` and `ammo_1p` are **nil for melee weapons**. So the xpcall result table `{true, weapon_3p, nil, weapon_1p, nil}` has non-deterministic length: `#t` could be 2, 3, 4, or 5 depending on Lua's internal boundary search.

This still produced nil-weapon-units in the inventory pipeline → infinity ammo HUD + corrupted 1P weapon rendering, ONLY visible when CWV's chained `mod:hook` was the next consumer (CWV re-emitted the nil values back to the engine). With CWV disabled, wt's truncation was less visible because the engine tolerated some nil returns; with CWV enabled, the chained re-emit cemented the corruption.

### Fixed
Capture the actual return count via `select("#", ...)` and pass it as `j` to `unpack` so nil holes are preserved:
```lua
local function _capture(...) return select("#", ...), { ... } end
local n, results = _capture(xpcall(handler, _error_handler, func, ...))
if results[1] then
    return unpack(results, 2, n)  -- explicit j preserves nil holes
end
```

### Bug timeline (per user investigation)
- v0.12.76 and earlier: no safe_hook wrapper → vanilla VMF mod:hook handled returns correctly → no bug
- v0.12.77 (Issue #26 fix shipped today): safe_hook introduced with `local ok, result_or_err` collapse → bug introduced (drops returns 2+)
- v0.12.78 (my first attempt at the fix shipped today): `unpack(results, 2)` without `j` → still broken (non-deterministic truncation)
- v0.12.79 (this release): `unpack(results, 2, n)` with explicit `j` → FIXED

### Lesson
The "table-pack the returns" idiom is necessary but not sufficient — you ALSO need `select("#", ...)` to know the true count when the function may return nils. This is the second time we hit a `VMF_RECIPES.md § 2` variant in 24 hours. Worth adding a regression test that asserts safe_hook'd functions preserve all positional returns INCLUDING nil values.

### Verification
1. Restart VT2. Load keep on Grail Knight (or any melee-weapon-equipping career).
2. Confirm ammo HUD shows finite number (NOT ∞).
3. Confirm 1P weapon model + grip renders correctly.
4. `/wt_regression_test` — `wt_safe_hook_installed` PASS.

## 0.12.78-dev (2026-05-25) — CRITICAL FIX: `safe_hook` wrapper multi-return collapse

### Why
v0.12.77's `_safe_hook.lua` shipped a textbook violation of `VMF_RECIPES.md` § 2 ("Hook wrappers collapse multi-returns"). The wrapper captured `local ok, result_or_err = xpcall(handler, ...)` and returned only `result_or_err` — silently dropping any 2nd / 3rd / 4th return value.

Several VT2 functions return multiple values:
- `GearUtils.spawn_inventory_unit` returns **4 values** (`weapon_unit_3p, ammo_unit_3p, weapon_unit_1p, ammo_unit_1p`) — wt v0.12.77 converted this site, so callers received only `weapon_unit_3p` and got `nil` for the other three.

### Symptoms (reported live by user on Grail Knight 2026-05-25 06:04)
- **Infinity-symbol ammo HUD** ← `ammo_unit_3p` collapsed to nil → ammo extension reads through missing unit → `nil` / `math.huge` arithmetic → ∞ glyph rendered.
- **First-person weapons rendered weirdly** ← `weapon_unit_1p` collapsed to nil → engine renders fallback / empty hands / wrong attachment.

### Fixed
`_safe_hook.lua` now table-packs the xpcall returns and `unpack(results, 2)` on success, preserving multi-return semantics:
```lua
local results = { xpcall(handler, _error_handler, func, ...) }
if results[1] then
    return unpack(results, 2)  -- Lua 5.1 unpack
end
```
Future-proofs every safe_hook'd function that returns multi-values, not just `spawn_inventory_unit`.

### Verification
1. Restart VT2. Load into keep on any Empire Soldier career.
2. Confirm ammo HUD shows a numeric value (NOT ∞) on any ranged weapon.
3. Confirm 1P weapon model + grip renders correctly.
4. Run `/wt_regression_test` — `wt_safe_hook_installed` should still PASS.

### Lesson
The new helper failed to apply its own repo's documented recipe. Adding a pre-merge gate that asserts `_safe_hook.lua` round-trips multi-returns through a test fixture is a follow-up worth filing.

## 0.12.77-dev (2026-05-25) — pcall-isolated `mod:safe_hook` wrapper (Issue #26)

### Why

A single `mod:hook` body that raises currently kills every later consumer
in the chain silently — no log, no error, just stops working. VMF's
`safe_calls.lua` xpcalls the outermost hook entry but does NOT isolate
consumers from each other when multiple mods stack hooks on the same
`(Class, method)`. Symptom in the wild: cosmetics_tweaker hook A raises
→ wt hook B never fires → user sees a missing feature with no diagnostic
log line. Fixes the diagnostic-cost side of GH #26 by giving wt a
drop-in-compatible wrapper that pcall-isolates each consumer's body.

### Added

- `weapon_tweaker/scripts/mods/weapon_tweaker/_safe_hook.lua` — module
  attaches `mod.safe_hook(self, class, method, fn)` and
  `mod.safe_hook_safe(self, class, method, fn)` methods. Wraps `fn` in
  xpcall; on error logs `[wt:safe_hook] <Class>.<method> raised: <err>`
  via `mod:error` (with stack trace from `Script.callstack()`), then
  falls through to `func(...)` so the original engine path and every
  later consumer in the chain stay intact.
- `mod:dofile("scripts/mods/weapon_tweaker/_safe_hook")` require near
  the top of `weapon_tweaker.lua`, after MOD_VERSION and before any
  hook call site, so `mod.safe_hook` exists by the time consumers below
  reach for it.
- New marker constant `CT_WT_SAFE_HOOK_MARKER_v0_12_74 =
  "wt-safe-hook-pcall-isolated"` set by `_safe_hook.lua` (read by the
  regression-test check below).
- `/wt_regression_test` check `wt_safe_hook_installed`: asserts the
  marker constant is present + both `mod.safe_hook` and
  `mod.safe_hook_safe` are callable functions. Catches accidental
  removal of the require in future refactors.
- New section in repo-root `VMF_RECIPES.md`: "Pcall-isolated hooks
  (mod:safe_hook)" — when to use vs raw `mod:hook`, the
  consumer-isolation principle, signature compatibility, and the v1
  scope (wt-local; cross-mod sharing is Wave-2).
- New version constant `MOD_VERSION = "0.12.77-dev"` (was `0.12.76-dev`).

### Changed

- 5 representative hook sites converted from `mod:hook` / `mod:hook_safe`
  to `mod:safe_hook` / `mod:safe_hook_safe`:
  - `SimpleInventoryExtension.wield` (local-player wield + 1P-hands
    capture).
  - `SimpleHuskInventoryExtension.wield` (husk-side per-unit state
    population for cross-character 3P remap).
  - `GearUtils.create_equipment` (in-game keep + mission spawn render
    path — path 1 of 3).
  - `GearUtils.spawn_inventory_unit` (cross-character 3P swap dispatch).
  - `LevelEndView._verify_weapon_data` (end-of-mission victory screen).
- Each converted site picks up the consumer-isolation contract: a raise
  in this mod's body logs + falls through to vanilla instead of killing
  every later mod's hook on the same Class.method.

### Anti-patterns avoided

- Did NOT convert every `mod:hook` call site in `weapon_tweaker.lua` —
  establish the pattern, demonstrate adoption, and stop. Per Issue #26's
  scope: 3-5 sites, not a wholesale refactor.
- `mod:safe_hook` is a drop-in compatible signature with `mod:hook` — no
  call-site changes needed beyond the method name.
- Self-contained inside `weapon_tweaker/` for v1. Cross-mod sharing
  (helper in `bt` or a `vmf_shared/` package) is a Wave-2 concern; not
  in scope here.

### Verification

- `VMBLauncher.exe build weapon_tweaker` — green.
- `/wt_regression_test` — `wt_safe_hook_installed` PASS expected
  (validates marker + method-callable + type checks).
- Behavior of the 5 converted hook sites is unchanged on the happy path
  (xpcall wraps the body but returns its result through unchanged).
- Issue #26 closed on this version.

---

## 0.12.76-dev (2026-05-25) — wt_debug_mode toggle + diagnostic event subscriptions + legacy widget migration

### Why

Two orphan checkboxes (`debug`, `enable_weapon_debug_logging`) were defined
in `_data.lua` since the legacy monolithic Tweaker era but never read by
`weapon_tweaker.lua` — `CODE_REVIEW.md` line 135 / 213 flagged them as
dead settings. Meanwhile, every cross-character 3P unit swap path (brace,
longbow, repeater pistol), per-spawn unit override resolution, weapon
scale/offset application, and the end-of-mission `_verify_weapon_data`
hook fired their `mod:info(...)` diagnostic lines unconditionally, which
makes the console log noisy for anyone running multiple Tweaker mods at
once. Consolidate into one user-facing toggle that gates the noisy
fine-grained diagnostics, leaving load-time status and warnings/errors
unchanged.

### Added

- `wt_debug_mode` checkbox under a new `diagnostics_group` ("Diagnostics")
  in `_data.lua`. Default OFF. Localization key + `_description` per
  `LOCALIZATION_STANDARD.md`.
- `_dbg(fmt, ...)` helper near the top of `weapon_tweaker.lua` (right
  after the load-time `mod:info` banner). Routes to `mod:info("[wt:dbg] " .. fmt, ...)`
  only when `wt_debug_mode` is on; no-op otherwise.
- One-time migration helper `_migrate_legacy_debug_setting()` runs at
  module load. If either `debug` or `enable_weapon_debug_logging` was
  set to `true` by an older version, it ORs them into `wt_debug_mode`
  and writes a `wt_debug_migration_v1 = true` sentinel so the migration
  never reruns. Clears both legacy keys on the same pass.
- StateIngame-enter loadout dump in `mod.on_game_state_changed(status,
  state_name)` — when debug is on and `status == "enter"` /
  `state_name == "StateIngame"`, dumps career_name + per-slot (item_key,
  item_type, template) for the local player via `inventory_system._career_name`
  + `equipment().slots`. Gated inside the helper too (belt-and-suspenders).
- Wield-time diagnostic in the existing `SimpleInventoryExtension.wield`
  hook. When debug is on, dumps slot_name, career_name, item_key,
  template, `anim_event_3p`, `wield_anim_3p` for each wield. Separate
  from the `_log_anims`/`/animlog`-driven block so users don't need to
  toggle two systems.
- New version constant `MOD_VERSION = "0.12.76-dev"` (was `0.12.75-dev` from
  the parallel Issue #26 `_safe_hook` landing).

### Changed

- 17 verbose `mod:info(...)` calls in `weapon_tweaker.lua` converted to
  `_dbg(...)`:
  - `[create_equipment] pre-resolved item_units` (per-spawn override
    resolution).
  - `[scale_probe]` one-time per-weapon slot_data field probe (2 lines).
  - `Scaled %s on %s` / `Offset %s on %s` per-spawn unit transforms (3
    lines).
  - `[wt brace-3p-swap]` enter / SKIP / hid-left-pistol / swapped (4 lines).
  - `[wt sp-longbow-crossbow]` enter / SKIP-hand / SKIP-career /
    SKIP-no-v_w3p / SKIP-package / SKIP-bolt-package / swapped /
    SKIP-pcall-nil (8 lines).
  - `[wt rp-pistol-handgun]` enter / SKIP-hand / SKIP-career /
    SKIP-no-v_w3p / SKIP-package / swapped (6 lines).
  - `[wt brace-3p-swap preview]` / `[wt sp-longbow-crossbow preview]` /
    `[wt rp-pistol-handgun preview]` per-equip swap confirmations (3
    lines).
  - `[verify_weapon_data]` LevelEndView hook entry + unwrap (2 lines).
  - `[team_previewer cb]` preview_items unwrap (1 line).
- Retired the `debug` + `enable_weapon_debug_logging` widget definitions
  in `_data.lua`. The keys live in user_settings.config for legacy
  users until the one-time migration clears them.

### Kept as `mod:info` (always print)

- `Weapon Tweaker v%s loaded` + `Weapon Tweaker: Baseline Active` —
  load-time / state-entry status.
- `[wt brace-3p-swap] force-loaded repeater 3P unit` + `[wt
  sp-longbow-crossbow] force-loaded %s` — one-time mod-init status.
- `[wt authentic-brace] applied` + `[wt kruber-longbow-zoom] applied` —
  one-time apply confirmations.
- `[regression] PASS/FAIL`, `[regression-test-command] registered`,
  `/dump`, `/dump_weapons`, `/sm_probe` outputs — command-driven, only
  fire when the user explicitly invokes.
- All `mod:warning` / `mod:error` calls — never gated.
- `[WIELD]` + `[animlog]` blocks gated behind `_log_anims` (toggled via
  `/animlog` chat command) — independent of the new VMF toggle.

### Anti-patterns avoided

- Single checkbox, single helper — no per-feature debug categories, no
  log-level enum.
- `wt_debug_mode` chosen as the key name (NOT `debug`, which would
  collide with the legacy widget and prevent the migration from
  distinguishing the two).
- `_dbg` calls inside the wield hook cache `mod:get("wt_debug_mode")`
  into a local `D` before the block to avoid two table lookups per
  wield.

### Verification

1. Restart VT2 with the mod enabled, load the keep.
2. Open VMF mod options, scroll to weapon_tweaker, expand "Diagnostics".
   Confirm `Debug Mode` checkbox is present with the description from
   `_localization.lua`.
3. With debug OFF (default): equip a brace of pistols on Kruber Foot
   Knight. Console log should show no `[wt:dbg]` lines and no
   per-spawn `[wt brace-3p-swap]` entries.
4. Toggle debug ON. Wield/unwield a weapon → expect `[wt:dbg] [wield]
   slot=slot_melee career=...` line per wield.
5. Start a mission. On state entry: `[wt:dbg] [loadout] StateIngame
   enter career=...` + per-slot lines.
6. Equip a cross-character weapon (e.g. brace on Kruber). The
   `[wt:dbg] [wt brace-3p-swap]` enter / swapped lines appear.
7. Confirm legacy migration: with `debug = true` in a stale
   user_settings.config, first load post-update should write
   `wt_debug_mode = true` + `wt_debug_migration_v1 = true` and clear
   the old keys (visible by re-opening user_settings.config).

## 0.12.73-dev (2026-05-24) — §15 belt-and-suspenders runtime test for v0.12.72 rawget conversion

### Why
Audit `.test_coverage_audit_2026-05-24.md` PARTIAL row 1: the v0.12.72 `ItemMasterList rawget` conversion was lint-covered (regression-lint.ps1 `strict-table-lookup`) but lacked an in-mod `_rt_register` runtime check. Per the §15 doctrine update appended this round, lint-covered fixes ALSO require a runtime regression test — both surfaces are needed for PASS.

### Added
- Source-pattern marker constant `CT_WT_ITEMMASTERLIST_RAWGET_MARKER_v0_12_73 = "wt-itemmasterlist-rawget-hardened"` near the top of `weapon_tweaker.lua`.
- `_rt_register("wt_itemmasterlist_uses_rawget", ...)` at the bottom of `weapon_tweaker.lua`. Two assertions:
  1. The marker constant retains its expected value (catches accidental revert / refactor deletion of the hardening block).
  2. `rawget(ItemMasterList, <known-bad-key>)` returns `nil` without raising (catches a future regression where ItemMasterList grows a metatable that breaks rawget).

### Verification
1. Restart VT2 with the mod enabled, load the keep.
2. Run `/wt_regression_test` in chat. Expect `PASS: wt_itemmasterlist_uses_rawget` alongside the four pre-existing checks.

## 0.12.72-dev (2026-05-23) — Issue #8: defensive rawget on user-input ItemMasterList lookups

### Why

`ItemMasterList[user_input_key]` Crashifies on unknown keys via vanilla's
strict `__index` metatable. A user typing `/forge nonexistent_weapon` (or
any future chat command, save-data drift, or peer-late-join race that
reaches an unrecognized key) would have hit an unrecoverable engine fatal
instead of a graceful nil-and-log. The repo-wide convention (already
practiced in `cosmetics_tweaker`) is to wrap every non-literal-key
lookup in `rawget()` so the strict-metatable bypass is unreachable.

### Changed

Converted every `ItemMasterList[<var>]` site to `rawget(ItemMasterList, <var>)`
in `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua`:

- `weapon_tweaker.lua:175` — `_strip_removed_kruber_unlocks` walk (was line 171).
- `weapon_tweaker.lua:208` — `apply_weapon_unlocks` strip pass.
- `weapon_tweaker.lua:226` — `apply_weapon_unlocks` add-back pass.
- `weapon_tweaker.lua:277` — `patch_career_actions_on_weapons` ability-action injection.
- `weapon_tweaker.lua:3835` — `/dump_weapons` chat-command dump loop.

All five sites previously iterated keys from internal literal tables
(`_kruber_removed_pairs`, `weapon_unlock_map`, sorted snapshot of
`pairs(ItemMasterList)`), so the strict-`__index` crash was unreachable
*today* but brittle on future refactors (e.g. if a user-input or
save-data key ever flows into one of these helpers). The conversion
matches the cosmetics_tweaker convention (lines 1305 / 1239 / 4555–4556)
and the file's own comment header at line 18 promising rawget hygiene.

The line-3961 `team_previewer.cb_hero_unit_spawned_skin_preview` hook
already used `rawget(ItemMasterList, item.item_name)` as part of the
v0.12.52-dev parade-crash fix — no change there.

### Verification

1. In the keep, type `/dump_weapons` — should print the same weapon
   dump as before (rawget on a known-good key is identical to direct
   index for present keys).
2. With cross-character weapon toggles ON, equip a cross-career weapon
   in the keep inventory previewer — unlock + ability-action injection
   paths exercise the four `apply_weapon_unlocks` /
   `patch_career_actions_on_weapons` sites.
3. (Future-proofing) Any new chat command in wt that accepts a weapon
   key as a chat-arg can now safely call `rawget(ItemMasterList, key)`
   following the same pattern.

## 0.12.71-dev (2026-05-23) — Reorder per-career weapon toggles into canonical order

### What

`weapon_tweaker_data.lua` and `weapon_tweaker_localization.lua` had each
career's `unlock_<career>_<weapon>` widget list in a mix of lore-grouped,
add-order, and ad-hoc orderings — different per character bucket. Both
files reordered in lockstep so every career follows one mechanical rule:

1. **Native weapons first** (alphabetical by base-weapon key after the
   `unlock_<career>_` prefix), with any `*_deus_01` entry sorting to the
   end of the native cluster.
2. **Cross-character ports next**, grouped by donor character in
   `es → dr → we → wh → bw` order, alphabetical within each donor
   bucket, donor `_deus_01` at end of donor group.
3. Ambiguous template-alias setting_ids (e.g. Saltzpyre's `es_1h_flail`,
   visually a Saltzpyre flail using the shared `es_1h_flail` ItemMasterList
   key) sort by their **literal setting_id prefix**, not in-game character
   ownership — keeps the rule mechanical and deterministic from the
   setting_id alone.

334 widget moves in data, 406 string moves in loc (loc has both melee +
ranged blocks intermixed per career, so loc moves > data moves). Every
move is a re-order only — no setting_ids added, removed, renamed, or
re-defaulted. `default_value` and per-career inclusions/exclusions
(e.g. `es_sword_shield_breton` only on merc + GK, drake-vs-steam-pistol
career split on Bardin, `wh_priest`'s unique melee pool) preserved
exactly as-is.

### Why

- **Discoverability:** new contributors and players adding a weapon need
  a predictable insert point. The mixed prior ordering required
  guessing the family group; new alphabetical-by-donor is mechanical.
- **Maintainability:** `feedback_alphabetical_order.md` mandates moving
  loc + data together. A mechanical ordering rule makes that
  enforceable — `sort -u` works for verification.
- **No internal-consistency cost:** all 4 careers per character bucket
  already shared the same melee/ranged ordering (audit confirmed), so
  reordering by mechanical rule preserves per-character symmetry while
  removing the historical drift.

Ordering rule + alternatives considered in
`_audit_wt_weapon_order.md` §4-5 (repo root). Peregrinaje was
evaluated as the canonical reference per user brief but rejected — its
`tweaks/new_weapons.lua` is a `pairs(DeusWeaponGroups)` walk and
`tweaks/weapon_options.lua` is a flat unordered registry; neither
provides a per-career ordering to mirror. Full rationale in §1-2 of
the audit doc.

### Files touched

- `scripts/mods/weapon_tweaker/weapon_tweaker_data.lua`
- `scripts/mods/weapon_tweaker/weapon_tweaker_localization.lua`
- `scripts/mods/weapon_tweaker/weapon_tweaker.lua` (MOD_VERSION bump only)

Pre-edit copies kept at `.bak.v0.12.70-dev` siblings of the two
touched scripts/mods files for diff insurance.

### Verification

1. Visual spot-check of `weapon_tweaker_data.lua:71-94` (merc native +
   ports — alphabetical + donor-grouped) and `weapon_tweaker_data.lua:428-435`
   (wh_priest — natives alphabetical, `es_1h_flail` correctly sorts under
   `es_*` donor bucket per ambiguous-alias rule).
2. Data/loc parity scan: both files have 428 unique `unlock_*` setting_ids,
   1:1 mapping (`set(data_sids) == set(loc_sids)`, no dups on either side).
3. Per-career divergences preserved: `es_sword_shield_breton` present
   only on `melee_es_mercenary` + `melee_es_questingknight`; Bardin
   drake-vs-steam-pistol career split intact; `wh_priest` 7-weapon
   pool + absent `ranged_wh_priest` group preserved.

## 0.12.70-dev (2026-05-23) — Remove polearm-preview diagnostic + defensive ItemMasterList audit

### Issue #7: Remove `_wt_polearm_preview_diag` diagnostic helper

The polearm preview diagnostic was scaffolded in v0.12.56 to log template/wield-event/animation data for a user-reported regression (Kruber Mercenary holding wrong stance on `es_halberd` / `es_2h_heavy_spear` preview). The regression was subsequently fixed in v0.12.64. The 4-line-per-equip diagnostic log noise is no longer earning its keep.

Deleted:
- `_POLEARM_DIAG_KEYS` whitelist table
- `_wt_polearm_preview_diag(self, item_name, slot)` function
- Call site in `MenuWorldPreviewer.equip_item` hook_safe
- Associated comment block

**Verification:** Inventory previewer works normally. No `[wt polearm-diag]` lines appear in logs.

### Issue #8: Defensive ItemMasterList lookup audit (resolved as side effect)

Audit pass to wrap user-input ItemMasterList lookups with `rawget(ItemMasterList, key)` pattern. The only remaining direct-index read with a dynamic key was inside `_wt_polearm_preview_diag` (deleted above), which took `item_name` from the hooked method parameter and validated it against `_POLEARM_DIAG_KEYS` before use. All other ItemMasterList accesses in the file iterate over hardcoded or self-validated key lists and are safe. Deletion of the diagnostic function resolves this audit item.

See CLAUDE.md Key conventions section for the pattern.

## 0.12.69-dev (2026-05-23) — Namespace `regression_test` chat command to avoid cross-mod collision

### Why
Seven mods registered `mod:command("regression_test", ...)`. VT2 chat commands are global — only the first mod wins, the rest fail silently with `[ERROR] (command): command name 'regression_test' is already used by another mod 'cim'`. Detected in PC-A log 2026-05-23 20:50:52.

### Changed
- `weapon_tweaker.lua` — renamed `regression_test` → `wt_regression_test`. Verification log line added at registration site.

### Verification
1. Restart VT2. No `[ERROR] (command):` line in console_logs about this command name.
2. Run `/wt_regression_test` in chat. Command fires and prints results.
3. Per memory `feedback_vt2_verify_before_shipping.md`.

## 0.12.67-dev (2026-05-22) — Authentic Brace: primary spread 3× → 2×

Single-shot LMB (action_one.default — primary mode of fire) was too inaccurate per user feel-test. `_AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT` dialled from 3.0 → 2.0; primary clone (`wt_authentic_brace_of_pistols_spread`) now scales every numeric leaf of the cloned `brace_of_pistols` spread template by 2× instead of 3×. Secondary mult unchanged at 9.0, so the rapid-fire / lock-target mode stays as wide-spread as before — the gap between primary and secondary widens to 4.5×.

## 0.12.66-dev (2026-05-22) — Add /regression_test command

### Added

- `/regression_test` chat command runs 4 in-game smoke checks for past fix-state: SimpleHuskInventoryExtension presence, weak-keyed per-3P-body anim-remap state shape, wh_priest's `weapon_unlock_map` excludes bows/crossbows/longbows, and the billhook 3P remap marker. Output: PASS/FAIL per check to chat plus log.

## 0.12.64-dev (2026-05-22) — Fixed: Kruber-on-billhook missing swing animations (regression dating to v0.12.55/56)

### Bug

User report: billhook animations broken after the v0.12.60-dev Kruber polearm preview fix. Three-subagent investigation (`_billhook_anim_diagnosis/`) traced the regression to **v0.12.55/56**, not v0.12.60. v0.12.60 made the codepath more visible but didn't introduce the bug.

### Root cause

`_WIELD_ANIM_CAREER_3P_PATCHES` (line ~1931, added v0.12.55) writes `Weapons.two_handed_billhooks_template.wield_anim_career_3p[es_*] = "to_polearm"` directly into the weapon template at boot. When Kruber wields Saltzpyre's billhook:

1. The patcher's value is already in the template at boot, so the **engine fires `to_polearm` directly** (not the original `to_2h_billhook`).
2. `Unit.animation_event` hook receives `to_polearm` with `career = es_huntsman` / `es_mercenary`.
3. Hook walks `_career_anim_redirect.to_polearm`:
   - `overrides[es_mercenary] = nil` → override branch skipped.
   - `prefix = "es_"`, `invert = nil`, career matches → `should_redirect = false`.
4. The two places `_resolve_3p_remap` is consulted to install `state.remap` (lines ~1127, ~1156) both bail. **`state.remap` stays nil.**
5. Subsequent billhook-specific attack events (`attack_swing_stab`, `attack_swing_left_diagonal`, `attack_swing_charge_stab`, etc.) fire raw on Kruber's polearm SM and silently no-op — polearm stance doesn't author billhook-named swing events.

Visible symptom: Kruber-on-billhook gets the correct stance (polearm) but **swing animations don't play**.

### Why v0.12.60 was innocent

v0.12.60's one-line `career and` short-circuit at line 1153 affects only the `_career_anim_redirect` path for **preview units** where `career == nil`. The Kruber-on-billhook in-mission case has a real career, so v0.12.60 doesn't change its behavior either way. Per subagent #46's git diff against HEAD, the redirect table is byte-identical pre/post v0.12.60. Per subagent #47's log scan, the preview path tested works clean. The regression is older and only manifests during actual wielding.

### Fix

Extended the unconditional weapon-change block at `weapon_tweaker.lua:1011-1026` with a fallback. When neither `_resolve_template_remap` nor `_resolve_key_remap` hits, ask `_resolve_3p_remap(event_name, career)` whether the wield event (which may have been patcher-rewritten) has an associated career-prefix remap in `_3p_remap_triggers`. The same lookup powers the override and redirect branches further down the hook; we're now also calling it from the wield-event path so the swing-event remap installs regardless of whether the wield event reached the hook in its original form or in the patcher-rewritten form.

### Symmetric coverage

Same fallback also fixes the inverse case: Saltzpyre wielding Kerillian's elf spear (the patcher rewrites `to_spear → to_2h_billhook` for `wh_*`). Pre-fix the swing-event remap installs only on the override-branch path; post-fix it installs from the wield-event path too.

### What v0.12.60's gate still does

The `career and` short-circuit at line 1153 stays. It blocks the redirect from firing on nil-career preview units (which would otherwise route polearm-class wields to whatever alt event the preview body happens to author — see v0.12.60's CHANGELOG entry). The new fallback is gated on the same `state and event_name:sub(1,3) == "to_"` check as the rest of the wield-event block, so preview units (no `state`) still don't reach it.

## 0.12.63-dev (2026-05-21) — Fixed: VMF crashify-exception in 10 trait-description tooltips

Per Section C of the 2026-05-21 audit, 10 trait-description strings at lines 550-588 of weapon_tweaker_localization.lua contained literal `%` characters (`+20%`, `5%`, etc.). VMF routes every localization through `safe_string_format` (`string.format`), so a single `%` triggers a `<<crashify-exception>>` event every time the tooltip is rendered — the same bug class fixed in gt 0.2.35. Escaped each occurrence to `%%`. No visual change (one displayed `%` after format).

## 0.12.62-dev (2026-05-21) — Move Big Rebalance master to bt (Tweaker: Buffs)

Refactored the wt-side Big Rebalance integration to depend on the new sister mod `bt` (Tweaker: Buffs). wt no longer ships its own copy of the 419-line `weapon_tweaker_big_rebalance_registrations.lua` (deleted; archived under `_big_rebalance_extract/deprecated_registration_files/`) and no longer exposes its own `br_master_enable_registrations` widget.

`BR.register_all()` is now a no-op shim. Per-feature toggles gate on `(get_mod("bt") or {}).is_br_active and get_mod("bt"):is_br_active()` instead of a local checkbox — when bt is installed and its master is on, wt's BR sub-toggles work; otherwise they silently no-op.

User-visible impact: subscribe to `bt` once, enable its master once, and any of wt/ct/et BR sub-toggles you flip will function. Removes the prior cross-mod sync rule.

## 0.12.61-dev (2026-05-21) — Core's Big Rebalance integration (opt-in)

Source mod: Core's Big Rebalance (Workshop ID `2705276978`,
"Weapon Balance" decompile). Credit to Core for the original
balance design; this is a re-implementation, not a redistribution.

Added the `[Big Rebalance]` group with the master toggle
`br_master_enable_registrations` and ~113 per-toggle widgets buckets
weapons / damage profiles / hooks / wield permissions / misc.
Every toggle defaults `false` — Big Rebalance is opt-in.

New files:
- `scripts/mods/weapon_tweaker/weapon_tweaker_big_rebalance.lua` — apply
  logic + function hooks (Flamethrower / Beam / TrueFlight start+fire).
- `scripts/mods/weapon_tweaker/weapon_tweaker_big_rebalance_defs.lua` —
  pure-data definitions for NewDamageProfileTemplates, ExplosionTemplates,
  and BuffTemplates that wt owns.
- `scripts/mods/weapon_tweaker/weapon_tweaker_big_rebalance_registrations.lua`
  — canonical alphabetical cross-mod registration list. Identical content
  ships in ct and et (diff-checked) per the gated-registration-divergence rule.

Master toggle `br_master_enable_registrations` runs a single pass that
writes every BR_REGISTRATIONS entry into DamageProfileTemplates /
ExplosionTemplates / BuffTemplates / StatBuffApplicationMethods and
appends each to NetworkLookup in sorted order, UNCONDITIONALLY on every
peer (per `feedback_vt2_gated_registration_diverges`). Per-toggle
changes that depend on those registrations only function when master is on.

Cross-mod dependencies left unimplemented in wt (per user direction):
- `DamageUtils.stagger_ai` / `apply_buffs_to_damage` / `calculate_damage`
  rewrites are et-owned; wt toggles that reference them work in
  isolation but reach full intent only with et's stagger rewrite.
- Talent buff bulk-registration is ct-owned; wt's registration list
  carries the *names* for index alignment but defers definitions to ct.

Open items (flagged in `impl_wt_summary.md`):
- `br_cog_rework` ships the speed/crit fields but defers the 19-entry
  chain-action / baked-sweep rewrites — too large for a clean
  toggle-gated implementation in one pass.
- `br_hook_shield_slam` is currently a gate-only toggle (no body); table-
  replacement half is covered by `br_shield_slam_replace`.
- `br_misc_status_dodge_count` surfaces only the `dodge_count = 2` knob;
  the full `GenericStatusExtension.init` rewrite stays with et.

## 0.12.60-dev (2026-05-20) — ROOT CAUSE: Unit.animation_event hook redirecting preview-unit wield events when career=nil

The polearm preview bug is finally root-caused. The v0.12.56 diagnostic data captured on 2026-05-20 (`console-2026-05-21-01.11.04-*.log`) showed:

```
item=es_halberd career=es_mercenary template=two_handed_halberds_template_1
  tpl.wield_anim=to_polearm wac3p[c]=to_polearm resolved=to_polearm
  has(resolved)=true has(to_polearm)=true has(to_2h_billhook)=false has(to_spear)=true
```

Every field that should be right IS right: the template patcher's `wield_anim_career_3p[es_mercenary] = "to_polearm"` landed, the engine resolved the wield event to `to_polearm`, AND Kruber's preview body authors `to_polearm` natively. So the event SHOULD fire and the pose should appear. Yet the pose was wrong.

The disconnect: `has(to_spear)=true` ALSO appears on Kruber's preview body. Kruber's preview body authors both `to_polearm` AND `to_spear` (the spear is one of the cross-character ports wt enables, so the engine pre-loads the spear SM on his body). That single line is what unlocks the trace.

### The redirect-with-nil-career bug

wt's `Unit.animation_event` hook (`weapon_tweaker.lua:909+`) intercepts every animation event globally. For a wield event on the previewer's character_unit:

1. `_unit_career_name(unit)` walks the unit's extension chain — `career_system` first, then `inventory_system`, then `Managers.player:owner`. The previewer's character_unit has **none** of these (it's a model unit, not a player unit), so the helper returns nil.
2. `is_local = _is_local_player_unit(unit)` is false (preview unit ≠ local player_unit), so the `_local_career_name()` fallback doesn't trigger either.
3. The hook continues with `career = nil`.
4. `career_redir = _career_anim_redirect["to_polearm"]` is the entry `{ alt = "to_spear", prefix = "es_", overrides = {...} }`.
5. The `overrides[career]` lookup short-circuits because `career` is nil. Good.
6. `matches_prefix = career and ...` evaluates to **nil → falsy**.
7. `should_redirect = career_redir.invert and matches_prefix or (not career_redir.invert and not matches_prefix)` reduces to `(nil and false) or (true and true)` = **true**.
8. `_safe_has_anim(unit, career_redir.alt)` — alt is `"to_spear"` — returns **true** on Kruber's preview body.
9. Hook fires `to_spear` instead of `to_polearm`. Kruber's body enters spear stance. Pose lands wrong.

Same flow corrupts every polearm-class wield on any preview body that authors the alt event:

| Wield event fired | Career resolves to | Redirect target | Hits |
|---|---|---|---|
| `to_polearm` (Kruber on halberd / Tuskgor) | nil | `to_spear` | Kruber preview body authors `to_spear` → redirects |
| `to_polearm` (Kruber on Saltzpyre billhook, via my wac3p remap) | nil | `to_spear` | same — redirects |
| `to_spear` (Kerillian on elf spear) | nil | `to_polearm` | Kerillian preview body authors `to_polearm` → redirects |
| `to_2h_billhook` (Saltzpyre on billhook) | nil | `to_polearm` | Saltzpyre preview body authors `to_polearm` → redirects |

Every native polearm-class preview was being silently routed to the wrong event. The "Kruber on billhook works" report from earlier was actually wrong — the redirect IS firing, but the wrong stance happened to look close enough to halberd stance that it passed visual inspection (both are `to_polearm`-class poses on the Empire skeleton).

### The fix

Gate `should_redirect` on `career` being non-nil. When career resolution fails (preview units, anonymous probes), don't redirect — fall through to native firing of the original event. The redirect mechanism is only meaningful for in-mission cross-character ports where the wielder's career is known; for anonymous units the safe behaviour is to let the body fire whatever event the engine sent it.

```lua
-- weapon_tweaker.lua:1100 (post-fix)
local should_redirect = career and (career_redir.invert and matches_prefix or (not career_redir.invert and not matches_prefix))
```

The `career_redir.overrides[career]` path (line 1080) already short-circuits on nil career and didn't need touching.

### Why this latent bug only surfaced now

The wt animation-event hook has carried this nil-career codepath since v0.9.x, but the bug stayed invisible because:

1. **The `_career_anim_redirect` table only had polearm-class entries with `alt` events the alternate-character bodies don't author.** Saltzpyre's preview body doesn't natively author `to_polearm`, Kerillian's body doesn't natively author `to_2h_billhook`, etc. So even when the hook tried to redirect, `_safe_has_anim` failed and the event fell through to native firing anyway — masking the bug.
2. **v6.11.0 (2026-05-18) didn't change `_career_anim_redirect` or `_safe_has_anim` — but Fatshark may have widened the preview body's SM-load coverage in an earlier patch.** Kruber's preview body authoring BOTH `to_polearm` AND `to_spear` is the missing ingredient that lets the redirect succeed and corrupt the pose. Whether this is new in v6.11.0 or older, the field repro is consistent with "some preview bodies started authoring more events than they used to".
3. **My v0.12.55/56/57 work added wield_anim_career_3p entries on the polearm templates**, which made the wield event actually reach the wt hook via the previewer's `_spawn_item_unit → Unit.animation_event` path with the right event name. Pre-v0.12.55, the previewer fired vanilla `wield_anim` (`to_2h_billhook` for billhook, etc.) — which Saltzpyre's preview body authored natively — so the redirect tried to fire on those events too but `_safe_has_anim` for the alt was probably false on the relevant bodies. The diag confirms the alt presence is what flipped.

The combination of "preview unit has no career_system" + "preview body authors the alt event" is what triggers the bug. Both conditions are necessary; the fix removes the first.

### Diagnostic kept (for now)

The polearm-diag from v0.12.56 / v0.12.59 stays in place for one or two more versions to confirm the fix on all four polearms. Once you eyeball halberd / Tuskgor / billhook / elf spear all looking right on every career, I'll delete the diag and tighten the file back up.

**Files changed:**
- `weapon_tweaker.lua` — MOD_VERSION 0.12.59 → 0.12.60; the should_redirect formula now requires `career` to be truthy before computing the prefix-match-based redirect decision. Single-line behavioural change; the rest of the hook is untouched.

## 0.12.59-dev (2026-05-20) — Polearm preview diagnostic: extend to `we_spear`, dump full `wield_anim_career_3p` table

User reports Mercenary halberd + Tuskgor still broken AND new repro on Kerillian native elf spear + Saltzpyre native billhook (both showing the previous weapon's stance). Static analysis says the engine's `world_hero_previewer.lua:1003` fallback chain (`wield_anim_career_3p[career]` → `wield_anim_career[career]` → `wield_anim`) should fire vanilla `wield_anim` for any career not in the `wield_anim_career_3p` table — and Kerillian (`we_*`) and Saltzpyre (`wh_*` for billhook) are not in those tables on their respective native weapons. Math says the fallback should hold; field repro says it doesn't.

I cannot find a code-level explanation from static read alone. Need the runtime data.

**Two changes to the existing v0.12.56 diagnostic:**

1. Added `we_spear` to `_POLEARM_DIAG_KEYS` so the probe also fires when Kerillian's elf spear is equipped in the keep.
2. The log line now also dumps the **full** contents of `tpl.wield_anim_career_3p` (sorted `k=v` pairs) and the presence of `to_1h_hammer` (for Warrior Priest path checks). The previous version only printed the single `wac3p[career]` lookup — useful for confirming the engine fallback hit, but not for catching the case where the patcher's writes never landed on the live template (revert by another mod, hot-reload artefact, wrong-template-name typo).

**What I'm trying to distinguish:**

- If the log shows `wac3p_table=nil` or empty `{}` on the affected items → the wt patcher never ran or another mod overwrote the field. Fix is at the patcher level.
- If the log shows the expected `wac3p_table={es_*=..., wh_*=...}` but `has(resolved)=false` → the resolved event genuinely isn't authored on the preview body. Fix is to pick a different target event (or force-load the state machine).
- If the log shows the expected table AND `has(resolved)=true` but the pose still looks wrong → some hook fires AFTER the wield event and corrupts the state machine. Fix is hook-ordering or a SM force-reset.

User repro path: open keep inventory, click halberd → Tuskgor → billhook → elf spear in turn, paste the four `[wt polearm-diag]` lines from the in-game log (`%APPDATA%\..\..\AppData\Roaming\Fatshark\Vermintide 2\console_*.log` on the current session).

**Files changed:**
- `weapon_tweaker.lua` — MOD_VERSION 0.12.58 → 0.12.59; `_POLEARM_DIAG_KEYS` gains `we_spear`; `_wt_polearm_preview_diag` log line extended with `wac3p_table=...` dump and `has(to_1h_hammer)` / `cunit_alive` fields.

## 0.12.58-dev (2026-05-20) — Kruber Longbow disable-zoom: switch to `zoom_condition_function` gate (game v6.11.0 fallout)

User reported that `kruber_longbow_disable_zoom` no longer killed the sniper zoom. Root cause: game v6.11.0 (Aussiemon/Vermintide-2-Source-Code @abe82ab4, 2026-05-18) dropped `aim_zoom_delay` on `longbows_empire_template.actions.action_two.default` from `2.0` → `0.22` (the only line that changed in `longbows_empire.lua`). The old wt disable patch leaned on `aim_zoom_delay = math.huge` to push the engine's `aim_zoom_time` beyond reach, but that's only the inner timing gate inside `action_aim.lua:128-134`:

```lua
if not self.zoom_condition_function or self.zoom_condition_function() then
    -- ...
    if not status_extension:is_zooming() and t >= self.aim_zoom_time then
        status_extension:set_zooming(true, current_action.default_zoom)
    end
end
```

Static read says `t >= math.huge` is never true and the patch should still hold, but the field repro after v6.11.0 says otherwise. Most plausible culprit: `scale_delay_value` (`action_aim.lua:13`) divides `aim_zoom_delay` by `ActionUtils.get_action_time_scale` per the active buff stack — if any buff pushes that scale to infinity or NaN, `math.huge / inf = NaN` and `t >= NaN` is false on every CPU but the field result was clearly inconsistent. Rather than chase the math, gate the OUTER check directly.

**Fix.** Set `aim.zoom_condition_function = function() return false end` in the disable branch. The engine's outermost gate at `action_aim.lua:128` then short-circuits the entire zoom block before it reaches any timer arithmetic, regardless of buffs / time scale / vanilla delay value. The old field writes (`aim_zoom_delay = math.huge`, `heavy_aim_flow_event = nil`, `heavy_aim_flow_delay = nil`, `default_zoom = nil`) stay in place as belt-and-suspenders.

**Manual-zoom branch** also sets `zoom_condition_function = function() return true end` explicitly — mirrors the shape vanilla writes (a closure returning `true`), so we don't drift from the template's authored type.

**v6.11.0 cross-check.** Diffed every weapon template and aim-related engine file between v6.10.0 (`5ff26df1`) and v6.11.0 (`abe82ab4`); the only relevant change is the `aim_zoom_delay = 0.22` constant. No new fields, no new code paths, so `zoom_condition_function` is and remains the right gate.

**No setting-change re-apply.** The patch still runs once at module init and the toggle is still labelled "Restart required" in localization. Mutating the shared template mid-mission would race with in-flight aim actions that already cached `self.aim_zoom_time`. Restart-on-toggle is the simplest invariant.

**Files changed:**
- `weapon_tweaker.lua` — MOD_VERSION 0.12.57 → 0.12.58; `_patch_kruber_longbow_zoom` rewritten to set `zoom_condition_function` as the primary gate; comment block updated with v6.10.0 vs v6.11.0 vanilla values and the rationale for switching gates.

## 0.12.57-dev (2026-05-20) — Remove Skullsplitter / Skull-Splitter+Shield / Bardin Hammer+Shield from Kruber's roster

Per user direction. Three cross-character weapons no longer offered to any Kruber career (`es_mercenary` / `es_huntsman` / `es_knight` / `es_questingknight`):
- `wh_1h_axe` — "Saltzpyre: Axe" (Skullsplitter)
- `wh_hammer_shield` — "Saltzpyre: Skull-Splitter and Shield"
- `dr_shield_hammer` — "Bardin: Hammer and Shield"

The three weapons stay available everywhere else they belong: `wh_1h_axe` remains native to Saltzpyre's three captain careers, `wh_hammer_shield` remains native to Warrior Priest plus the Saltzpyre cross-character row, and `dr_shield_hammer` remains native to all four Bardin careers. Only the four Kruber career rows lose the offering.

**Three surfaces touched:**
- `weapon_tweaker.lua` — removed all twelve `(es_*, weapon)` pairs from `weapon_unlock_map` (lines 31-34). Added `_kruber_removed_pairs` + `_strip_removed_kruber_unlocks` and wired it as the first step of `apply_weapon_unlocks` so existing users who had any of the toggles set true still get their stale `item.can_wield[<es_career>]` entry stripped on next init (or next setting change). Idempotent — runs cheaply on every reapply.
- `weapon_tweaker_data.lua` — deleted twelve `unlock_es_*_<weapon>` checkbox widget entries across the four Kruber melee groups. Removed `_cwv_managed_settings` table + `_strip_cwv_widgets` helper + its call site — they only stripped `wh_1h_axe` widgets when CWV was installed, and with `wh_1h_axe` gone from wt entirely there's nothing to strip. The CWV detector loop was simplified to just `_has_cim`.
- `weapon_tweaker_localization.lua` — deleted the matching twelve `unlock_es_*_<weapon> = { en = "..." }` strings across the four Kruber localization blocks.

Also cleaned `_cwv_managed` in `weapon_tweaker.lua` (line ~63): removed the dead `wh_1h_axe = true` entry from each of the four Kruber career rows. The CWV variant `cwv_es_axe_shield` (Kruber's "Imperial Axe and Shield") is unaffected — that variant is owned end-to-end by the `character_weapon_variants` mod and never went through wt's unlock map.

**Files changed:**
- `weapon_tweaker.lua` — MOD_VERSION 0.12.56 → 0.12.57; weapon_unlock_map trimmed; `_cwv_managed` cleaned; `_kruber_removed_pairs` + `_strip_removed_kruber_unlocks` added; first line of `apply_weapon_unlocks` calls the stripper.
- `weapon_tweaker_data.lua` — 12 widget rows removed; dead CWV-strip code excised; detector loop simplified.
- `weapon_tweaker_localization.lua` — 12 label rows removed.

## 0.12.56-dev (2026-05-20) — Kruber polearm preview: add explicit es_* entries + diagnostic probe

User repro of v0.12.55-dev showed Mercenary (Kruber) still holding the previous-weapon stance when previewing **native** `es_halberd` and `es_2h_heavy_spear` in the keep inventory. Both templates have vanilla `wield_anim = "to_polearm"`; Kruber's 3P body authors `to_polearm` natively (proven by `_career_anim_redirect.to_polearm.alt = "to_spear"` only applying to non-es_ careers — meaning es_ careers are expected to play `to_polearm` natively). So the engine's `world_hero_previewer.lua:1003` fallback chain (`wield_anim_career_3p[career]` → `wield_anim_career[career]` → `wield_anim`) should fire `to_polearm` on Kruber's preview body and the polearm stance should appear. Why it doesn't is unknown from static read.

**Two changes:**

1. **Explicit `es_*` entries** added to both polearm templates' `wield_anim_career_3p` (alongside the existing wh_* entries from v0.12.55). This forces the wield event to fire through the same code path as the billhook template's es_* entry that the user already confirmed works pre-patch — bypassing whatever interaction is short-circuiting the engine's `wield_anim` fallback. The entries map every Kruber career to `"to_polearm"`, which is what the fallback was supposed to deliver anyway, so the runtime behavior on the in-mission path is unchanged.

2. **Diagnostic helper `_wt_polearm_preview_diag`** wired into the `MenuWorldPreviewer.equip_item` hook. On every equip of `es_halberd` / `es_2h_heavy_spear` / `wh_2h_billhook`, logs the resolved wield event and whether the character_unit has it, plus the presence of the three candidate `to_*` events. Output goes to `[wt polearm-diag]` in the in-game log. Use one repro pass to capture the data, then delete the helper once the root cause is identified. Cost: 4 log lines per polearm equip while debugging.

If the diagnostic shows `has(to_polearm)=false` on Kruber's `character_unit`, the preview body genuinely lacks the polearm 3P SM — that would mean we need a different target event (probably `to_2h_hammer`) or a state-machine force-load. If `has(to_polearm)=true` but the stance is still wrong, the issue is elsewhere (e.g. another mod's hook firing on the same event and corrupting the SM).

**Files changed:**
- `weapon_tweaker.lua` — MOD_VERSION 0.12.55 → 0.12.56; expanded `_WIELD_ANIM_CAREER_3P_PATCHES.two_handed_halberds_template_1` and `.two_handed_heavy_spears_template` with es_* keys; added `_wt_polearm_preview_diag` helper and wired it into the consolidated equip_item hook.

## 0.12.55-dev (2026-05-20) — Inventory wield-stance: close the polearm gap (halberd / Tuskgor / billhook)

Adds the missing `wield_anim_career_3p` template patches for the three polearm-class cross-character pairs that had in-mission redirects (`_career_anim_redirect`, line ~225) but no template-side patch — so the keep inventory previewer (`MenuWorldPreviewer`) was firing a wield event the target body doesn't author, and the cross-character wielder held the prior weapon's idle stance.

**New gaps closed:**
- **`two_handed_halberds_template_1`** (Kruber's halberd `es_halberd`) on `wh_captain` / `wh_bountyhunter` / `wh_zealot` → `to_2h_billhook`. Saltzpyre now enters his billhook stance when previewing the halberd in the keep, matching the in-mission behavior the `_career_anim_redirect.to_polearm` override at line 239-240 already produced.
- **`two_handed_heavy_spears_template`** (Kruber's Tuskgor spear `es_2h_heavy_spear`) on the same three Saltzpyre careers → `to_2h_billhook`. Same root cause and same fix.
- **`two_handed_billhooks_template`** (Saltzpyre's billhook `wh_2h_billhook`) on `es_mercenary` / `es_huntsman` / `es_knight` / `es_questingknight` → `to_polearm`. Kruber's halberd stance, matching `_career_anim_redirect.to_2h_billhook` (line 247-248). User confirmed this preview already looked correct pre-patch, so this entry is belt-and-suspenders — it bakes the in-mission redirect into the template so both paths agree natively without depending on engine-fallback timing.

**Refactor:** the previous `_WE_SPEAR_WIELD_3P_OVERRIDES` table + `_patch_elf_spear_template_for_non_elves` function (single-template, wield-only) is replaced by a declarative `_WIELD_ANIM_CAREER_3P_PATCHES` table + one `_apply_wield_anim_career_3p_patches` applier covering all four polearm templates. New gaps surface as additional table rows instead of additional patcher functions. The four pre-existing patchers that ALSO do per-action `anim_event_3p` remap loops (brace / longbow_empire / longbow_template_1 / repeating_pistol) are kept as-is — they encode action-table logic that doesn't fit the declarative table.

**Why this couldn't be discovered earlier from the in-mission behavior alone:** `_career_anim_redirect` only fires through wt's `Unit.animation_event` hook. The inventory previewer doesn't go through that hook — it reads `wield_anim_career_3p` directly off the weapon template. So a missing template patch silently broke the preview pose while in-mission play looked fine, hiding the gap until a player paid attention to the keep stance. Documented in the patch block's comment.

**wh_priest** is intentionally absent from every entry — his row in `weapon_unlock_map` (line 49) has no polearm/spear/billhook/bow/crossbow, so any entry would be dead per `feedback_vt2_no_bows_on_warrior_priest` and the no-T-pose-stance audit closed in v0.12.48-dev.

**Files changed:**
- `weapon_tweaker.lua` — MOD_VERSION 0.12.54 → 0.12.55; replaced lines ~1838-1892 (the elf-spear-only patch block) with a declarative `_WIELD_ANIM_CAREER_3P_PATCHES` table containing all four polearm templates + one unified applier.

## 0.12.54-dev (2026-05-20) — Extend `TeamPreviewer` defense to invalid-key (Shape B) crashes

Extends the v0.12.53 belt-and-suspenders pre-hook to also handle the case where `item.item_name` is a **string that isn't in `ItemMasterList`** — not just the nested-table shape. PrincessLyndsey's crash repro on v0.12.52 used `we_maidenguard` as the leaking value; `we_maidenguard` is a **career-name string** (used in `can_wield` lists per `item_master_list.lua:14`), NOT an `ItemMasterList` key. Vanilla `team_previewer.lua:120-121` does `ItemMasterList[item_name]` then `item_template.slot_type` — when `item_name` is a string-but-not-a-key, the lookup returns nil under the strict-lookup metatable and the next line crashes on nil-index.

The v0.12.53 hook only unwrapped table-shape values, so it left career-name string leaks unguarded. Now the same pre-hook also `rawget`s the candidate against `ItemMasterList` (per memory `feedback_vt2_strict_lookup_rawget` — strict-lookup tables must use rawget for existence probes) and clears `item.item_name = nil` if the lookup misses. The downstream `if item_name then` guard at `team_previewer.lua:119` then skips that slot cleanly. No effect when `item.item_name` is a valid IML key (the common case).

Root-cause investigation deferred: the upstream code path that wrote `"we_maidenguard"` (a career name) into a `preview_items[i].item_name` slot is unknown. Could be a stale loadout reference, a versus parading-view bug (`versus_team_parading_view_v2.lua:597` reads `career_settings.preview_items[2].item_name` and forwards it verbatim — a CWV variant or career-name leak there would propagate), or an older bailout still in flight from a Fatshark change we haven't tracked. The Shape B guard turns the crash into a silent skip + warning log, which is the right user-facing behavior regardless of which upstream produces the bad data.

## 0.12.53-dev (2026-05-20) — Belt-and-suspenders parade-crash defense at `TeamPreviewer.cb_hero_unit_spawned_skin_preview`

End-of-mission parade crash recurred at `team_previewer.lua:120: attempt to index local 'item_template' (a nil value)` — same bailout-shape root cause documented in v0.12.25-dev (vanilla `LevelEndView._verify_weapon_data` writes `verified_weapon = { item_name = career_settings.preview_items[1] }`, where `preview_items[1]` is a `{ item_name = "..." }` table not a string, so `verified_weapon.item_name` ends up holding a nested table). Reproduced 2026-05-20 with PrincessLyndsey666 hosting Chaos Wastes, finishing on `we_maidenguard` (career_settings.preview_items[1] = `{ item_name = "we_spear" }`). The "is not wieldable" diagnostic print fired (vanilla `level_end_view_v2.lua:326`), confirming the bailout path was taken — but the existing post-hook on `_verify_weapon_data` (`weapon_tweaker.lua:3628-3645`) **did not log the unwrap**, despite the hook being registered (log line 1256: `[MOD][wt][INFO] (hook): Hooking '_verify_weapon_data' from [LevelEndView]`). Whether the hook never fired or the mutation was lost between hook exit and `team_previewer.cb_hero_unit_spawned_skin_preview` reading `preview_items[2].item_name` is unresolved — no other mod hooks `_verify_weapon_data`, the deployed bundle includes the fix code, and the running version is v0.12.52-dev (log line 1231).

**Two changes:**

1. **Entry-point instrumentation on the existing `_verify_weapon_data` post-hook** — log `player.name / career_index / weapon_slot / weapon.item_name` at the TOP of the wrapper (before `func(...)`). On the next repro this distinguishes "hook never fired" from "hook fired but mutation didn't propagate." Cheap, info-level only.

2. **Belt-and-suspenders pre-hook on `TeamPreviewer.cb_hero_unit_spawned_skin_preview`** — walk `hero_data.preview_items` BEFORE the loop body runs, and for any `item.item_name` that's a `{ item_name = "..." }` table, unwrap to the inner string (or clear to nil if unexpected). This catches the broken shape at the frame just above the actual crash site (`team_previewer.lua:117-120` does `local item_name = item.item_name; ItemMasterList[item_name]`), regardless of which upstream path produced the bad data. No-op for the well-formed-string case.

Per memory `feedback_redundant_safeguards_ok.md` — the user endorses belt-and-suspenders writes when redundancy is cheap and the missed-path failure is silent. A nil-index crash on the parade view is exactly such a silent failure (no recovery, kicks the player to keep).

**Risk:** Very low. Pre-hook walks a 2-element table and rewrites a field that's already broken if shape matches the nested-table case. Non-bailout success path (where `item.item_name` is a string) untouched. Hook target is `TeamPreviewer` (defined in `scripts/ui/views/team_previewer.lua`), used only by `LevelEndView._setup_team_previewer` per grep — versus paths use `VersusTeamParadingViewV2` which also goes through TeamPreviewer per the same grep so they get the same coverage.

**Bug B (note, not addressed here):** Vanilla `BackendInterfaceCommon.can_wield(we_maidenguard, "we_dual_wield_sword_dagger")` returned false despite that pair being natively wieldable per `dumps/weapon_native_careers.txt:59`. Likely cause: `apply_weapon_unlocks` at `weapon_tweaker.lua:80-122` strips careers destructively then re-adds only toggle-enabled ones. The bailout fires whenever the user toggles a NATIVE (career × weapon) pair OFF — but the strip-rebuild walks `weapon_unlock_map` rather than checking against a native baseline. Worth a separate fix that distinguishes "wt-added cross-career unlock" from "vanilla-native pair", but tracking as follow-up — out of scope for this patch.

**Files changed:**
- `weapon_tweaker.lua` — MOD_VERSION bump 0.12.52 → 0.12.53; entry-point `mod:info` on the existing `_verify_weapon_data` hook (~L3629); new `TeamPreviewer.cb_hero_unit_spawned_skin_preview` pre-hook block appended after the verify hook (~L3650+).

## 0.12.52-dev (2026-05-19) — Moonfire puff visible to remote peers

Adds `mod:hook_safe` registrations on `PlayerProjectileHuskExtension` (`hit_enemy` / `hit_level_unit` / `hit_non_level_unit`) so the cosmetic puff (and the AOE-revert FX) plays on every peer that sees the arrow, not just the shooter's own machine. Previously only `PlayerProjectileUnitExtension` was hooked — that extension only runs on the shooter's client, so remote peers (host or other clients, depending on who fired) never saw the puff. Same husk-vs-self class-pair gap as the cosmetics_tweaker reload-paint bug (see `feedback_vt2_husk_extension_class_pair`).

The husk extension carries all the same fields `_wt_moonfire_on_hit` reads, so the existing callback works as-is. Refactored the hook registration to a small loop over the two class names and three method names — adds resilience if future VT2 patches add a fourth hit method.

AOE-revert side stays safe: `DamageUtils.create_explosion` already gates damage on `is_server`, so calling it from a husk hook on clients spawns FX but does no damage — exactly the per-peer pattern the prior comment block described as the intent.

## 0.12.51-dev (2026-05-19) — Moonfire AOE revert crash fix

Fixes host-side crash `area_damage_system.lua:347: attempt to index local 'explosion_template' (a nil value)` introduced in v0.12.49-dev when the **`moonfire_aoe_revert`** toggle was on and any Moonfire arrow impact reached the damage-buffer drain (queue-overflow path or next-frame `_update_aoe_damage_buffer`).

Root cause: `_MOONFIRE_AOE_TEMPLATE` was an unregistered local table with no `.name` field. `DamageUtils.create_explosion` forwards `explosion_template.name` to `AreaDamageSystem.add_aoe_damage_target` (17th positional arg), which writes it onto the ring-buffer entry. `_damage_unit` later calls `ExplosionUtils.get_template(name)` → `ExplosionTemplates[name]`. With `name = nil` the lookup returned nil and the next line (`explosion_template.explosion`) crashed. Vanilla templates avoid this because `explosion_templates.lua` runs `for name, t in pairs(ExplosionTemplates) do t.name = name end` at engine boot — but mods load after that loop fires, so any mod-defined template must populate `.name` itself **and** register into `ExplosionTemplates` so the late-stage lookup succeeds.

Fix: name the template `"wt_moonfire_aoe_revert"`, set `.name` explicitly, and write into `ExplosionTemplates[name]` at module init.

## 0.12.50-dev (2026-05-19) — Kruber Longbow zoom overrides (disable / manual)

Two new toggles under **Weapon Overrides**, both default OFF. Restart required (template patch applied at module init).

- **`kruber_longbow_disable_zoom`** — strips the longbow's delayed sniper-style heavy zoom entirely. Sets `aim_zoom_delay = math.huge` on `action_two.default` and nil's both `heavy_aim_flow_event` (`"lua_heavy_zoom"`) and `heavy_aim_flow_delay`. Holding right-click still draws the bow and applies the planted-charging movement debuff, but the camera never zooms.
- **`kruber_longbow_manual_zoom`** — replaces the heavy-zoom flow with Kerillian-longbow-style instant manual zoom. Adds `default_zoom = "zoom_in"`, sets `aim_zoom_delay = 0.01`, nil's the heavy-zoom fields. Hold right-click → bow draws AND zooms immediately; release to unzoom. **Overrides** `disable_zoom` when both are on (more specific).

### Affected templates

Patches both `Weapons.longbow_empire_template` and `Weapons.longbow_empire_tutorial_template` so the tutorial mission stays consistent. The cross-character port to Saltzpyre (`_patch_longbow_empire_template_for_saltzpyre`) lives on the same template, so any zoom override propagates to wh_captain / wh_bountyhunter / wh_zealot when they wield the Empire Longbow via the cross-character unlock.

### Implementation

Patcher runs once at module init, after `_patch_longbow_empire_template_for_saltzpyre` and after the moonfire AOE block. No hooks — direct mutation of the template's `action_two.default` aim action. Vanilla flow event `lua_heavy_zoom` is just unhooked from this template; the flow event itself still exists for any other content that might fire it (currently nothing else does).

## 0.12.49-dev (2026-05-19) — Moonfire Bow: pre-nerf AOE revert + cosmetic puff toggles

Two new toggles under **Weapon Overrides**, both default OFF. Restores (or just visually echoes) the small magical AOE every Moonfire Bow arrow used to detonate with before the nerf.

- **`moonfire_cosmetic_puff`** — cosmetic only. On every Moonfire arrow impact (enemy / level geometry / non-level prop) spawns one `fx/wpnfx_we_deus_01_impact` particle effect at the hit position. No damage, no friendly fire, no AOE — purely the lost visual.
- **`moonfire_aoe_revert`** — gameplay revert. Same hit paths, but routes through `DamageUtils.create_explosion` with a 1.5m radius (0.75m max-damage core) using the existing `poison_aoe` damage profile and an `attacker_power_level_offset = -0.5` cut so it reads as splash, not as a primary-damage detonation. `no_prop_damage` and `no_friendly_fire` are set. Visual is a 4-puff cluster (center + 3 jittered ~0.3m offsets) so the revert reads as visibly bigger than the cosmetic puff. **Overrides the cosmetic toggle** when both are on.

### Multiplayer model

Both hooks run on every peer's `PlayerProjectileUnitExtension` instance — VFX plays on every peer's screen for everyone's Moonfire arrows. Damage is gated by `_is_server` inside `create_explosion`, so host applies the AOE damage authoritatively; clients run the VFX-only path even though they call the same function. No `NetworkLookup` writes, no `LevelSettings` changes — lobby `combined_hash` is unaffected, so toggling on after the fact does not change which lobbies you can join (see `[[reference-vt2-lobby-combined-hash]]`).

### Why hook_safe on three hit paths

`PlayerProjectileUnitExtension` exposes `hit_enemy`, `hit_level_unit`, and `hit_non_level_unit` (plus `hit_player` for friendly-fire — intentionally skipped to avoid puffs on teammate hits). All three carry `hit_position` as the same argument index; one shared `_wt_moonfire_on_hit(self, hit_position)` callback covers them. `hook_safe` is correct because we do not need to modify the return value or short-circuit vanilla — we only piggyback the hit event.

### `we_deus_01` prefix match

Match is on `string.sub(self.item_name, 1, 10) == "we_deus_01"` so every Moonfire skin / illusion / variant carries the toggle through. CWV does not yet ship a `cwv_we_deus_01_*` variant; if one lands, the matcher needs widening.

## 0.12.48-dev (2026-05-19) — Drop Warrior Priest from Kerillian Volley Crossbow port (closes priest-ranged audit)

Third and final pass of the no-bows-on-Warrior-Priest audit (`feedback_vt2_no_bows_on_warrior_priest.md`). The user rule's body explicitly enumerates volley-crossbows; team-lead acked extending the strip to the surviving Priest+`we_crossbow_repeater` (Kerillian Volley Crossbow) entry that shipped pre-v0.12.x.

### Three surfaces touched

- `weapon_unlock_map.wh_priest`: drop trailing `"we_crossbow_repeater"`. Priest's row is now MELEE-ONLY (`wh_dual_hammer`, `es_1h_flail`, `wh_flail_shield`, `wh_1h_hammer`, `wh_hammer_shield`, `wh_hammer_book`, `wh_2h_hammer`).
- `_data.lua`: remove `unlock_wh_priest_we_crossbow_repeater` widget. The `ranged_wh_priest` group is now empty, so the whole group is removed and replaced with a comment marker citing the rule. (Empty VMF groups can render as label-with-nothing; clean removal avoids that visual oddity.)
- `_localization.lua`: remove `unlock_wh_priest_we_crossbow_repeater` label AND the now-orphaned `ranged_wh_priest = "Ranged: Warrior Priest"` group label (the group itself is gone).

No `_WIELD_3P` table to touch — `we_crossbow_repeater` cross-character relies on the global `_career_anim_redirect.to_repeating_crossbow_elf` (line 221) which redirects non-`we_*` careers to `to_repeating_crossbow`. Priest's body authors neither event, so the entry silently no-op'd pre-strip (he held prior-weapon idle stance while equipping the Volley Crossbow). Now functionally gated at `can_wield` instead — Priest can no longer equip the weapon at all.

### Audit close

Full `grep wh_priest` across `weapon_tweaker.lua`, `_data.lua`, `_localization.lua` returns:
- `weapon_unlock_map.wh_priest`: melee-only.
- `_data.lua melee_wh_priest` group: 7 melee unlocks (`wh_dual_hammer`, `es_1h_flail`, `wh_flail_shield`, `wh_1h_hammer`, `wh_hammer_shield`, `wh_hammer_book`, `wh_2h_hammer`). All ✓.
- `_data.lua` ranged_wh_priest: absent (comment marker in place).
- `_localization.lua` Priest labels: 1 group label (`melee_wh_priest`) + 7 weapon labels, all melee. All ✓.
- `_career_anim_redirect` (line 218+) Priest overrides: all target `to_1h_hammer` / `to_1h_hammer_shield` (melee). ✓
- `_suffix_career_map` (line 267+) Priest entries: all target `_1h_hammer` / `_1h_hammer_shield` suffixes (melee). ✓
- `_SP_LONGBOW_CROSSBOW_WIELD_3P` (line 1708): comment cites rule, Priest absent. ✓
- `_WE_LONGBOW_CROSSBOW_WIELD_3P` (line 1760): comment cites rule, Priest absent. ✓
- elf-spear patcher (line 1850+): Priest comments only document the unrelated `we_spear` exclusion (Priest never unlocks Kerillian's spear). ✓

**Zero ranged cross-character `wh_priest` entries remain. The audit is closed.** Future ports targeting bows / crossbows / longbows / volley-crossbows must continue to omit Priest per the rule.

### Previously-shipped state

`unlock_wh_priest_we_crossbow_repeater` was `default_value = false`, so opt-in only. Any player who toggled it on:
- The "Ranged: Warrior Priest" group header is gone from VMF settings on next reload. Their checkbox state survives in settings.config but maps to nothing readable.
- `apply_weapon_unlocks` strips Priest from `ItemMasterList.we_crossbow_repeater.can_wield` on next reload. Existing Volley Crossbow inventory items on Priest stay in inventory but the equip slot is empty until they swap.
- Previously-broken 3P render (Priest holding prior-weapon idle stance while equipping the Volley Crossbow) is gone.

## 0.12.47-dev (2026-05-19) — Drop Warrior Priest from historical Empire Longbow on Saltzpyre port

Companion to v0.12.46-dev. Team-lead acked extending the no-bows-on-Warrior-Priest rule (`feedback_vt2_no_bows_on_warrior_priest.md`) to the **pre-existing** Empire Longbow on Saltzpyre port (`es_longbow` on `wh_priest`, shipped pre-v0.12.x in `_SP_LONGBOW_CROSSBOW_WIELD_3P`). v0.12.46-dev stripped Priest from the NEW Port A (`we_longbow`); v0.12.47-dev does the same for the OLDER port that predated the rule.

Same four surfaces as the v0.12.46-dev change:
- `weapon_unlock_map.wh_priest`: drop trailing `"es_longbow"`.
- `_data.lua`: remove `unlock_wh_priest_es_longbow` checkbox.
- `_localization.lua`: remove `unlock_wh_priest_es_longbow` label.
- `_SP_LONGBOW_CROSSBOW_WIELD_3P`: drop `wh_priest = "to_crossbow"` entry; comment updated to cite the rule and the pre-v0.12.47-dev shipped state.

### Previously-shipped state

The widget defaulted to `false`, so the most likely impact on existing players is zero — Priest+Empire-Longbow was an opt-in pairing and was visually broken when toggled on anyway. For any player who DID toggle it on:
- The checkbox disappears from the VMF settings menu on next reload.
- `apply_weapon_unlocks` (`weapon_tweaker.lua:80`) strips Priest from `ItemMasterList.es_longbow.can_wield` on next reload because the unlock map no longer carries the pair. Their existing Empire-Longbow item on Priest stays in inventory (modded items don't lose backend entries), but the equip slot will show empty and the weapon won't be wieldable until they switch careers or pick a different ranged.
- The previously-broken 3P render (Priest holding his prior weapon's idle pose while firing arrows) is gone; vanilla Priest ranged options are unaffected.

### Audit complete

`wh_priest` now appears in NO `_<PORT>_WIELD_3P` table and in NO ranged cross-character unlock anywhere in the mod. Audit signal: `grep -n wh_priest weapon_tweaker.lua weapon_tweaker_data.lua weapon_tweaker_localization.lua` returns only `weapon_unlock_map.wh_priest` (with no ranged cross-character entries) and the comment citations in the two wield-3p tables. The rule is now enforced in code as well as memory.

## 0.12.46-dev (2026-05-19) — Drop Warrior Priest from Port A (Elf Longbow on Saltzpyre)

Per the user rule established 2026-05-19 (memory `feedback_vt2_no_bows_on_warrior_priest.md`): never add `wh_priest` to bow/crossbow/longbow cross-character ports. Priest's 3P body skeleton authors only the six universal wields plus `to_2h_hammer` — no `to_longbow`, no `to_crossbow`, no `to_repeating_crossbow`. Cross-character ranged ports that include him would produce no playable wield motion on his body.

Port A (`we_longbow` on Saltzpyre, shipped in v0.12.44-dev / consolidated under v0.12.45-dev) was authored before the rule was set and included Priest as a parity entry. Removed in three places this version:
- `weapon_unlock_map.wh_priest`: drop trailing `"we_longbow"`.
- `_data.lua`: remove `unlock_wh_priest_we_longbow` checkbox.
- `_localization.lua`: remove `unlock_wh_priest_we_longbow` label.
- `_WE_LONGBOW_CROSSBOW_WIELD_3P`: drop `wh_priest = "to_crossbow"` entry; comment updated to cite the rule and the dead-vocabulary diagnosis.

### Audit on the pre-existing es_longbow port

The older `_SP_LONGBOW_CROSSBOW_WIELD_3P` (Empire Longbow on Saltzpyre, shipped pre-v0.12.x) also lists `wh_priest = "to_crossbow"` plus carries `"es_longbow"` in `weapon_unlock_map.wh_priest`. That predates the rule. Pending team-lead confirmation before stripping shipped behavior — the entry is currently dead/no-op (Priest's `can_wield` already includes `es_longbow` so the checkbox is functional, but his body still can't render `to_crossbow` so the stance fires nothing). Will follow up once team-lead acks the audit. The new rule is documented in memory regardless so future ports won't repeat the mistake.

No build/deploy risk: this is a strict subtraction. Port A's other three Saltzpyre careers (`wh_captain`, `wh_bountyhunter`, `wh_zealot`) are unaffected. No new tables, no new helpers, no new force-load paths.

## 0.12.45-dev (2026-05-19) — Cross-character ports: Kerillian Longbow on Saltzpyre + Saltzpyre Repeating Pistol on Kruber

Two new cross-character ports shipped in the same iteration cycle via the canonical `CROSS_CHARACTER_PORT_RECIPE.md` procedure. Both follow the seven-step recipe end-to-end. v0.12.44-dev shipped Port A standalone; v0.12.45-dev adds Port B and consolidates both under one CHANGELOG block.

### Port A — `we_longbow` (Kerillian's Longbow) on all four Saltzpyre careers → empire crossbow 3P

The four Saltzpyre careers (`wh_captain`, `wh_bountyhunter`, `wh_zealot`, `wh_priest`) can now equip Kerillian's elf longbow (`we_longbow`); on Saltzpyre's body it renders as the empire crossbow 3P mesh with crossbow firing/zoom animations. 1P stays the elf longbow (1P is universal across characters — `feedback_1p_animations_universal.md`).

Sibling to the existing `es_longbow` (Kruber's empire longbow) port on Saltzpyre. Same 3P target mesh, same anim_event vocabulary, same 3P unit paths — so the in-mission + preview swap helpers are **reused with the dispatch predicate widened**; no new force-load and no new unit constants required. This is the "reusing an existing helper for sibling ports" pattern documented in `CROSS_CHARACTER_PORT_RECIPE.md` Section 2.

**Surface changes:**
- `weapon_unlock_map`: append `"we_longbow"` to all four Saltzpyre rows.
- `_data.lua`: four `unlock_wh_*_we_longbow` checkboxes (`default_value = false`).
- `_localization.lua`: four "Kerillian: Longbow" labels.
- `weapon_tweaker.lua`:
  - New `_patch_longbow_template_1_for_saltzpyre()` mutating `Weapons.longbow_template_1`:
    - `wield_anim_career_3p[wh_*] = "to_crossbow"`
    - per-action `anim_event_3p` for `attack_shoot_fast → attack_shoot`, `attack_shoot_fast_last → attack_shoot_last`, `draw_bow → to_zoom`. Crossbow SM has no `*_fast` variants; `to_zoom` is the crossbow's aim-hold (`action_two.default.anim_event`).
  - In-mission `GearUtils.spawn_inventory_unit` dispatcher: predicate widened to `item_data.name == "es_longbow" or item_data.name == "we_longbow"`. `_wt_longbow_3p_swap_apply` helper body is fully source-template-agnostic — substitutes `Weapons.crossbow_template_1` linking to dodge the `a_unwielded_bow` non-pcall-safe engine fatal (`feedback_vt2_unit_node_not_pcall_safe`).
  - Preview `MenuWorldPreviewer.equip_item` helper `_wt_longbow_preview_swap_apply`: predicate widened the same way.

### Port B — `wh_repeating_pistols` (Saltzpyre's Repeating Pistol) on all four Kruber careers → repeating handgun 3P

The four Kruber careers (`es_mercenary`, `es_huntsman`, `es_knight`, `es_questingknight`) can now equip Saltzpyre's revolving Repeating Pistol (`wh_repeating_pistols`); on Kruber's body it renders as the empire repeating handgun 3P mesh with repeating-handgun firing/aim animations. Right-hand-only weapon (no left-hand secondary, no ammo unit) — simpler equip-side shape than the brace port. 1P stays the Repeating Pistol.

**Vocabulary overlaps cleanly:** source `repeating_pistol_template_1` fires `attack_shoot` (action_one.default + action_one.bullet_spray) and `lock_target` (action_two.default); target `repeating_handgun_template_1` authors `attack_shoot`, `attack_shoot_last`, `attack_shoot_fast`, `attack_shoot_fast_last`, `lock_target`, `lock_target_loop`, `reload` natively. Per-action `anim_event_3p` remap table is intentionally **empty** — only `wield_anim_career_3p[es_*] = "to_repeating_handgun"` is needed. This is the case Section 2 step (e) of the recipe calls out as "skip step (e) when every source action's anim_event already exists in the target SM vocabulary unchanged."

**New helper required (not a dispatcher-widen).** The sibling-port checklist hits 4/5 against the brace hook (same target unit `_BRACE_REPEATER_3P_UNIT`, same right-hand orientation, no ammo unit on either, neither needs left-hand secondary handling for B1) but fails on the fifth criterion: the source template's `right_hand_attachment_node_linking.third_person.wielded` references **weapon-mesh-side nodes** (`lock_hammer`, `rotator`, `trigger_t1`) that don't exist on the repeating handgun mesh — linking via them would `Unit.node` engine fatal that bypasses pcall (sibling of crashify://f210b3b7). The brace's table is simpler (`j_rightweaponattach → 0` only) and survives the swap unchanged; we don't get that luxury here. Solution: substitute the **target template's** `right_hand_attachment_node_linking.third_person.wielded` for the link call in both the in-mission and preview paths.

**Surface changes:**
- `weapon_unlock_map`: append `"wh_repeating_pistols"` to all four Kruber rows.
- `_data.lua`: four `unlock_es_*_wh_repeating_pistols` checkboxes (`default_value = false`).
- `_localization.lua`: four "Saltzpyre: Repeating Pistol" labels.
- `weapon_tweaker.lua`:
  - New `_patch_repeating_pistol_template_1_for_kruber()` mutating `Weapons.repeating_pistol_template_1`: sets `wield_anim_career_3p[es_*] = "to_repeating_handgun"`. No per-action remap (vocabulary overlap).
  - New `_wt_repeating_pistol_3p_swap_apply` helper parallel to `_wt_longbow_3p_swap_apply`. Spawns `_BRACE_REPEATER_3P_UNIT`, links via `Weapons.repeating_handgun_template_1.right_hand_attachment_node_linking.third_person.wielded`, mirrors vanilla `_wield_slot` visibility (hide on local 1P, keep visible on husks — `feedback_vt2_husk_extension_class_pair` lessons inherited from the brace swap).
  - New `_wt_repeating_pistol_preview_swap_apply` helper parallel to `_wt_longbow_preview_swap_apply`. Mutates `entry.unit_name = _BRACE_REPEATER_3P_UNIT` AND `entry.unit_attachment_node_linking = handgun_tpl.right_hand_attachment_node_linking.third_person` (whole `third_person` table, covering both wielded and unwielded paths so the holster-mount also avoids the node fatal).
  - Dispatcher predicates added to both consolidated hooks (`GearUtils.spawn_inventory_unit` + `MenuWorldPreviewer.equip_item`) for `item_data.name == "wh_repeating_pistols"`.
  - **No new force-load**: `_BRACE_REPEATER_3P_UNIT` is already force-loaded by `_force_load_brace_repeater_3p_unit()` at mod init — Port B reuses the same target unit as the brace swap.

### Verification matrix (per the recipe doc)

Pending QA (`qa` teammate, task #5). For each port, walk all eight cells of the verification matrix in `CROSS_CHARACTER_PORT_RECIPE.md` Section 5:
- Keep inventory preview: target career rotates with target mesh in target wield stance. Port A = Saltzpyre with crossbow+bolt in `to_crossbow`; Port B = Kruber with repeating handgun in `to_repeating_handgun`.
- Solo mission: 3P body shows target mesh + target firing/attack anims on every action. 1P unchanged.
- Multiplayer host viewing husk + vice versa: both halves show target mesh.
- Wield/unwield cycle: stance re-enters cleanly; no stuck idle stance, no engine fatal on holster (`feedback_vt2_no_tpose_default_stance.md` — missing-event no-ops would hold the previous weapon's idle, not T-pose).
- Toggle setting off, re-enter keep: career stripped from `can_wield`.

Diagnostic log signatures per port:
- Port A: `[wt sp-longbow-crossbow] enter ...` then `[wt sp-longbow-crossbow] swapped 3P bow→crossbow ...`
- Port B: `[wt rp-pistol-handgun] enter ...` then `[wt rp-pistol-handgun] swapped 3P pistol → handgun ...`

## 0.12.43-dev (2026-05-17) — Longbow swap: add entry/skip diagnostic logging (parity with brace)

The brace→repeater swap has had verbose `enter` / `SKIP (<reason>)` log lines on every entry path since v0.12.37, which made it possible to see exactly why the swap was silently bailing for husks. The longbow→crossbow helper never got the same treatment — it only logged on the SUCCESS path, so every silent bail (hand check, career check, `v_w3p` nil, package not loaded, pcall returned nil) was invisible in the host's console.

After a v0.12.42 fresh launch with Saltzpyre wielding `es_longbow` (host viewing the husk), the host log contains the force-load lines at startup but ZERO `[wt sp-longbow-crossbow]` entries during gameplay. The swap is bailing somewhere before the success log. Without entry-level logging we can't tell which gate fires.

Added the same diagnostic pattern as the brace hook:
- **Entry log**: `enter hand=<...> husk=<bool> owner_unit_3p=<bool> career=<...> owner_known=<bool> owner=<name> v_w3p=<bool> v_a3p=<bool>` — captures all decision inputs.
- **SKIP log per bail path**: `hand != left`, `career not Saltzpyre`, `v_w3p was nil`, `crossbow 3P package not loaded`, `bolt 3P package not loaded`, `pcall returned nil`.

No functional change. Just observability. After this lands, a fresh test session will tell us exactly which branch the husk path is hitting.

## 0.12.42-dev (2026-05-17) — Elf spear preview stance: bake wield_anim_career_3p

### Bug

Saltzpyre wielding Kerillian's spear (`we_spear`) showed the wrong stance in the keep inventory preview — vanilla `to_spear` polearm pose instead of the billhook stance he uses in-mission. (In-mission was already correct via the `_career_anim_redirect.to_spear` → `to_2h_billhook` redirect for `wh_*` overrides.)

### Root cause

The `_career_anim_redirect` table intercepts `Unit.animation_event(unit_3p, "to_spear")` calls. The in-mission wield flow goes through this hook, so the redirect fires and Saltzpyre enters billhook stance.

The keep inventory previewer (`MenuWorldPreviewer`) sets up the character model's wield animation by reading `wield_anim_career_3p` (or `wield_anim_3p`, or `wield_anim`) directly off the weapon template at spawn time. It doesn't fire the wield event through a path our `Unit.animation_event` hook intercepts. The vanilla elf spear template has `wield_anim = "to_spear"` only (no per-career 3P override), so the previewer fired `to_spear` on Saltzpyre's body and got vanilla polearm-stance.

### Fix

Bake the in-mission `_career_anim_redirect.to_spear.overrides` mapping into the spear template's `wield_anim_career_3p` at mod init — parallel pattern to `_patch_brace_template_for_kruber` and `_patch_longbow_empire_template_for_saltzpyre`:

```lua
Weapons.two_handed_spears_elf_template_1.wield_anim_career_3p = {
    wh_captain      = "to_2h_billhook",
    wh_bountyhunter = "to_2h_billhook",
    wh_zealot       = "to_2h_billhook",
    es_mercenary    = "to_polearm",
    es_huntsman     = "to_polearm",
    es_knight       = "to_polearm",
    es_questingknight = "to_polearm",
}
```

Both paths (in-mission + preview) now resolve to the correct stance natively. Kerillian and unmapped careers fall back to `wield_anim = "to_spear"` as before — wood-elf SM authors `to_spear` natively. The `_career_anim_redirect.to_spear` entry stays — it still covers any re-fires of `to_spear` through the animation_event path (push-attack stance resets, etc.).

### Why only Saltzpyre + Kruber

Per `weapon_unlock_map`, the elf spear is unlocked for Kerillian (native), all four Kruber careers, and Saltzpyre's wh_captain / wh_bountyhunter / wh_zealot. Bardin, Sienna, and wh_priest don't unlock it — entries for them would be dead.

## 0.12.41-dev (2026-05-17) — Remove Sienna's Sword (`bw_sword`) from all Saltzpyre careers

Dropped `bw_sword` from `weapon_unlock_map` for `wh_captain` / `wh_bountyhunter` / `wh_zealot`, and removed the three matching VMF checkboxes + localization entries. `apply_weapon_unlocks` will strip any previously-added Saltzpyre entries from `ItemMasterList.bw_sword.can_wield` on next reload. Sienna native access (Adept / Scholar / Unchained / Necromancer) is unchanged. `wh_priest` never had this entry. No remap/scale/grip state touched.

## 0.12.40-dev (2026-05-17) — Remove Bardin's Crossbow (`dr_crossbow`) from all Saltzpyre careers

Dropped `dr_crossbow` from `weapon_unlock_map` for `wh_captain` / `wh_bountyhunter` / `wh_zealot`, and removed the three matching VMF checkboxes + localization entries. `apply_weapon_unlocks` will strip any previously-added Saltzpyre entries from `ItemMasterList.dr_crossbow.can_wield` on next reload. Bardin native access (Ranger / Ironbreaker / Slayer / Engineer) is unchanged. `wh_priest` never had this entry. No remap/scale/grip state touched.

## 0.12.39-dev (2026-05-17) — Hide brace left pistol on husks too

### Bug

After v0.12.38 made the brace→repeater swap visible to the host on remote-player Kruber husks, the **left-hand brace pistol** remained visible alongside the swapped repeater on the right hand. Same `wh_brace_of_pistols` issue: the template renders two pistols (one per hand), and the spawn hook only swaps the right hand.

### Root cause

Two parallel issues, both rooted in the husk/self-owned class split:

1. The `mod:hook_safe("SimpleInventoryExtension", "show_third_person_inventory", ...)` re-hider only fires on the self-owned class. Per `unit_extension_templates.lua` (line 71), husks use `SimpleHuskInventoryExtension`, which has its own `show_third_person_inventory` method that our hook doesn't cover. Same trap recorded in [[feedback_vt2_husk_extension_class_pair]] and just hit yesterday in v0.12.37.

2. Even if we hook the husk class, `SimpleHuskInventoryExtension._wield_slot` never calls `self:show_third_person_inventory()` at the end (the self-owned `simple_inventory_extension.lua:692` does, but the husk version doesn't). So a hook on the husk method wouldn't fire on initial wield — only on later state-driven visibility toggles (ghost mode, grabbed-by-tentacle).

### Fix

Two-part:

- **Hook both classes' `show_third_person_inventory`** — factored the existing hook body into `_hide_brace_left_pistol(self, show)` and registered it on both `SimpleInventoryExtension` and `SimpleHuskInventoryExtension`. Belt for any later visibility toggles that go through this method.
- **Hide directly in the spawn hook** — added a branch in the `GearUtils.spawn_inventory_unit` hook for `hand == "left"` + brace + Kruber career, hiding `v_w3p` immediately via the same `Unit.has_visibility_group/set_visibility` branching the existing hook uses. Suspenders for the initial-wield case on husks where the show_third_person_inventory path doesn't fire.

### Why both

- The spawn-time hide is the primary fix and covers the initial wield case for both local and husk.
- The show_third_person_inventory hook stays for later toggles (e.g. a husk coming out of ghost mode re-enables 3P inventory, which would otherwise re-show the left pistol).

## 0.12.38-dev (2026-05-17) — Brace/longbow swap: don't hide 3P unit on husks

### Bug

After v0.12.37 made the brace→repeater swap correctly fire on the host for remote-player Kruber husks (confirmed by the diagnostic log line `swapped 3P brace → repeater on career=es_mercenary (husk=true)`), the host STILL saw the vanilla brace mesh instead of the repeater.

### Root cause

Both the brace→repeater and longbow→crossbow swap bodies called `Unit.set_unit_visibility(new_unit, false)` unconditionally. That's correct for the LOCAL player path — vanilla `_wield_slot` (both `SimpleInventoryExtension` and `SimpleHuskInventoryExtension`) hides the 3P weapon when a 1P unit exists, because the local player sees their hands in 1P, not their 3P body. But for HUSKS, there's no 1P, so vanilla LEAVES the 3P unit visible — that's exactly how other players see the held weapon. Our unconditional hide inverted that for husks: the new repeater unit was rendered invisible, while the original brace had been `mark_for_deletion`-ed, so the host saw the brace mesh for a frame or two (before deletion landed) and then nothing.

### Fix

Both swap helpers (brace at the `GearUtils.spawn_inventory_unit` hook, longbow at `_wt_longbow_3p_swap_apply`) now gate the visibility hide on `owner_unit_1p`:

```lua
if owner_unit_1p then
    Unit.set_unit_visibility(new_unit, false)
end
```

Matches vanilla `simple_husk_inventory_extension.lua:750-756` (and the equivalent block in `simple_inventory_extension.lua`) which uses `if right_hand_weapon_unit_1p then ... set_unit_visibility(weapon_unit_3p, false)`.

### Diagnostic log update

The brace swap's success log now also reports the visibility decision (`vis=true` = unit was made invisible, i.e. local player path; `vis=false` = unit stays visible, i.e. husk path).

## 0.12.37-dev (2026-05-16) — Multiplayer husk fixes: husk wield hook + robust career lookup + brace-swap diagnostics

### Bug

Two multiplayer issues, same root cause class:
1. **Animation remap** (regression in v0.12.35's per-unit migration): the wield hook hooked only `SimpleInventoryExtension.wield`. Remote-player husks use a different class — `SimpleHuskInventoryExtension` — so `_unit_state[husk_unit]` never got populated. The animation_event hook had no per-husk weapon info and fell back to "no remap" for husks.
2. **Brace → repeater 3P unit swap**: didn't fire on the host's view of a client's Kruber wielding the brace. The user (client) saw their own Kruber as repeater correctly, but the host saw the brace mesh.

### Root cause (both issues)

Per `unit_extension_templates.lua`:
- `self_owned_extensions` (lines 12 / 43) → `SimpleInventoryExtension`
- `husk_extensions` (lines 71 / 90) → `SimpleHuskInventoryExtension`

The two classes share no method inheritance. `SimpleHuskInventoryExtension.wield` (line 314 in source) is a separate codepath. It DOES call `GearUtils.spawn_inventory_unit` (line 666), so the brace hook's `mod:hook("GearUtils", "spawn_inventory_unit", ...)` registration DOES fire for husks — but `_unit_career_name(owner_unit_3p)` was reading from the inventory extension's `_career_name`, which is only set when the husk extension's init received a Player object whose `career_name()` was non-nil at that exact moment (race-prone on lobby-formed remote players).

### Fix

- **`_unit_career_name`** — switched to using `career_system` extension as the primary source. `CareerExtension` is attached to both local player_units AND husks (per `unit_extension_templates.lua` line 75) and its `init` sets `self._career_name` directly from `career_data.name` (`career_extension.lua:23`) — no race, no Player-object dependency. The inventory_system and `Managers.player:owner` paths remain as fallbacks.

- **New `mod:hook("SimpleHuskInventoryExtension", "wield", ...)`** — populates `_unit_state[self._unit]` for remote-player husks, mirroring the SimpleInventoryExtension hook from v0.12.35. Factored the state-population body into `_populate_unit_state_from_wield` so the two hook callbacks stay in lockstep.

- **Brace swap diagnostic logging** — every brace spawn now logs (filtered, at most 2 lines per equip): `hand`, `husk=true/false` (derived from `owner_unit_1p == nil`), career resolution, owner-player resolution, and skip reason if the swap bailed. Lets us see exactly what the host's machine reports for a remote Kruber wielding the brace.

### Notes

- The brace swap hook's existing claim "Husks: same hook fires because remote-player spawn flows through the same `GearUtils.spawn_inventory_unit`" was correct about the hook firing. The actual gap was career detection, not hook registration.
- See [[feedback_vt2_husk_extension_class_pair]] (new memory): for any feature that needs to behave correctly for remote players, audit whether the hooked class has a `Husk*` sibling per `unit_extension_templates.lua`. Hook both, or hook a global function (like `GearUtils.spawn_inventory_unit`) that both classes route through.

## 0.12.36-dev (2026-05-16) — Remove Saltzpyre's Axe (`wh_1h_axe`) from all Kerillian careers

Dropped `wh_1h_axe` from `weapon_unlock_map` for `we_waywatcher` / `we_maidenguard` / `we_shade` / `we_thornsister`, and removed the four matching VMF checkboxes + localization entries. `apply_weapon_unlocks` will strip any previously-added Kerillian entries from `ItemMasterList.wh_1h_axe.can_wield` on next reload. Saltzpyre native access (Captain / Bounty Hunter / Zealot) and Kruber CWV-managed access are unchanged. No remap/scale/grip state touched.

## 0.12.35-dev (2026-05-16) — Per-unit animation remap state (multiplayer fix)

### Bug

Cross-career weapon 3P animations played correctly only on the local player's screen for **their own** weapon. Other players' cross-career weapons rendered with the wrong remap (or none at all) unless the local viewer happened to be holding the same weapon on the same career.

### Root cause

The remap system tracked weapon and remap state as a **single set of globals** (`_current_weapon_template`, `_current_weapon_key`, `_3p_weapon_remap`, `_last_remap_template`). The `SimpleInventoryExtension.wield` hook updated these only when `self._unit == player.player_unit`, so husks never registered. The `Unit.animation_event` hook then applied the (local-player) remap to every 3P body it processed — including remote-player husks — so husks animated as if they were holding the host's weapon on the host's career.

### Fix

Per-unit state, weak-keyed by the 3P body unit:

```lua
local _unit_state = setmetatable({}, { __mode = "k" })
-- entries: { template, key, remap, last_remap_id }
```

- **`SimpleInventoryExtension.wield` hook** — lifted the `self._unit == player.player_unit` gate around state capture. Now populates `_unit_state[self._unit]` for every wield, on every player (local + husks + bots). The `_local_fp_unit` capture stays local-gated (we only need to identify *our own* 1P hands for the redirect-skip early-return).

- **`Unit.animation_event` hook** — all references to the old globals replaced with `_state_for(unit)` lookups. Career resolution switched from `_local_career_name()` to `_unit_career_name(unit)` (falls back to the local career only if the unit lookup fails). 1P early-return moved AHEAD of the state work so 1P events don't allocate state entries.

- **Flail direct-redirect block** (Saltzpyre's flail H1/H2 and Sienna's flaming flail H2 cross-career fixes) — was previously `is_local`-only because the global `_current_weapon_key` only tracked the local viewer. Now reads `state.key` per-unit and uses the unit's own career, so a remote Saltzpyre with es_1h_flail also gets the fix on the host's screen.

- **`to_*` remap reset** — also per-unit now. Each husk re-resolves its own remap on weapon switch via `state.last_remap_id`.

- **`/info` command** — now queries the local player's `_unit_state` entry for the displayed 3P-remap name.

### Notes

- The per-unit table is weak-keyed (`__mode = "k"`) so dead units release automatically without a separate cleanup pass.
- Bot inventories use the same `SimpleInventoryExtension`, so this also fixes bot 3P anims (which were previously rendered with the local viewer's remap).
- 1P universality is preserved — only the 3P body unit and remote husks ever enter the redirect/remap blocks. Per `feedback_animation_remap_rules`, 1P animations work on every character with every weapon and are never touched.

## 0.12.34-dev (2026-05-16) — Wide curation pass: Bardin / Kerillian / Sienna

Continuing the curation pass from v0.12.33. All removals trim default-OFF widgets and the matching unlock-map entries; no remap/scale/grip state is touched (those tables either had no entries for the removed careers, or had entries for unrelated careers that still wield the weapon).

**Bardin (all 4 careers) lose:**
- `wh_1h_hammer` — Saltzpyre's Skull-Splitter
- `wh_hammer_shield` — Saltzpyre's Skull-Splitter & Shield

**Kerillian (all 4 careers) lose:**
- `dr_1h_axe`, `dr_1h_hammer` — Bardin's Axe / Hammer
- `wh_2h_sword`, `wh_1h_hammer`, `wh_1h_falchion` — Saltzpyre's Greatsword / Skull-Splitter / Falchion
- `bw_sword`, `bw_1h_crowbill` — Sienna's Sword / Crowbill
- `es_1h_sword`, `es_halberd`, `es_2h_heavy_spear` — Kruber's Sword / Halberd / Tuskgor Spear

**Sienna (all 4 careers) lose every non-`bw_` weapon** — keeping only the seven Sienna-native melee options (`bw_1h_crowbill`, `bw_dagger`, `bw_ghost_scythe`, `bw_flame_sword`, `bw_1h_flail_flaming`, `bw_1h_mace`, `bw_sword`) plus the staff ranged options. Removed: `dr_1h_axe`, `dr_1h_hammer`, `we_1h_sword`, `es_1h_mace`, `wh_1h_axe`, `wh_1h_falchion`, `es_1h_flail`, `wh_1h_hammer`. The Necromancy Staff (`bw_necromancy_staff`) remains correctly exclusive to Necromancer.

## 0.12.33-dev (2026-05-16) — Bulk curation pass + fix `bow_root` in-game crash on Saltzpyre + longbow

## 0.12.33-dev (2026-05-16) — Bulk curation pass + fix `bow_root` in-game crash on Saltzpyre + longbow

### Crash fix — `crashify://92f9907f-45a1-4688-b415-441287faa34d`

`[Script Error]: bow_root` when Saltzpyre (any career) equipped Kruber's longbow IN-MISSION (not the keep preview — that path was fixed in v0.12.29). Sibling bug to v0.12.29's `a_unwielded_bow` crash: `_wt_longbow_3p_swap_apply` linked the spawned crossbow `new_weapon` using the LONGBOW template's `left_hand_attachment_node_linking.third_person.wielded` table, which references `bow_root` — a node that exists on the bow weapon mesh but not on the crossbow mesh. Engine `Unit.node` raised a fatal that bypassed our pcall (`feedback_vt2_unit_node_not_pcall_safe`). Fix: pull the wielded linking from `Weapons.crossbow_template_1.left_hand_attachment_node_linking.third_person.wielded` instead — same approach as the preview fix, applied to the in-game wielded code path. The brace→repeater swap doesn't hit this class because the brace and repeater templates happen to share compatible weapon-side node names; longbow and crossbow do not.

### Curation: remove never-functional cross-character options

Removed unlock entries (and matching VMF widgets + localization) where the underlying animation / skeleton compatibility was never going to work cleanly. All removals are default-OFF toggles, so no user with a saved-ON setting is silently disabled — but the menu noise is gone.

**Bardin (all 4 careers — Ranger / Ironbreaker / Slayer / Engineer) lose:**
- `bw_sword` — Sienna's Sword
- `wh_dual_hammer` — Saltzpyre's Dual Skull-Splitters

**Saltzpyre Captain / Bounty Hunter / Zealot lose:**
- `dr_1h_axe`, `dr_dual_wield_hammers`, `dr_1h_hammer` — Bardin axe / dual hammers / hammer
- `we_2h_sword` — Kerillian's Greatsword
- `bw_1h_flail_flaming` — Sienna's Flaming Flail

**Warrior Priest additionally loses (16 weapons stripped; WP now offers only its native moveset + a couple compatible holdouts):**
- All four Bardin entries above plus `dr_shield_hammer`
- `we_spear`, `we_1h_sword`
- `es_halberd`, `es_1h_mace`, `es_mace_shield`, `es_1h_sword`, `es_2h_heavy_spear`
- `wh_1h_axe`, `wh_2h_billhook`, `wh_1h_falchion`
- `bw_1h_crowbill`, `bw_1h_flail_flaming`, `bw_sword`

WP retains: `wh_dual_hammer`, `es_1h_flail`, `wh_flail_shield`, `wh_1h_hammer`, `wh_hammer_shield`, `wh_hammer_book`, `wh_2h_hammer`, `we_crossbow_repeater`, `es_longbow`.

`apply_weapon_unlocks` will strip the now-unmanaged career entries from each weapon's `ItemMasterList.<key>.can_wield` on next reload. The `_3p_remap_triggers` and `_weapon_scale_overrides` tables for the affected weapons are untouched — they still serve any character/career combo that legitimately wields them.

## 0.12.32-dev (2026-05-16) — Remove Saltzpyre's Axe (`wh_1h_axe`) from all Bardin careers

Dropped `wh_1h_axe` from `weapon_unlock_map` for `dr_ranger` / `dr_ironbreaker` / `dr_slayer` / `dr_engineer`, and removed the four matching VMF checkboxes + localization entries. `apply_weapon_unlocks` will strip any previously-added Bardin entries from `ItemMasterList.wh_1h_axe.can_wield` on next reload. Saltzpyre / Kruber (CWV-managed) / wh_priest access unchanged. The `_cwv_managed.es_*.wh_1h_axe = true` rows are for Kruber and untouched.

## 0.12.31-dev (2026-05-16) — Remove Bardin's Great Hammer (`dr_2h_hammer`) + Bardin's Hammer (`dr_1h_hammer`) from all Kruber careers

Dropped both keys from `weapon_unlock_map` for `es_mercenary` / `es_huntsman` / `es_knight` / `es_questingknight`, and removed the eight matching VMF checkboxes + localization entries (4 careers × 2 weapons). `apply_weapon_unlocks` will strip any previously-added Kruber entries from `ItemMasterList.dr_1h_hammer.can_wield` and `dr_2h_hammer.can_wield` on next reload. Bardin / wh_priest access is unchanged. `_weapon_scale_overrides.dr_1h_hammer.we_` (Kerillian-only) is untouched.

## 0.12.30-dev (2026-05-16) — Remove Sienna's 1h Sword (`bw_sword`) from all Kruber careers

Dropped `bw_sword` from `weapon_unlock_map` for `es_mercenary` / `es_huntsman` / `es_knight` / `es_questingknight`, and removed the four matching VMF checkboxes + localization entries. `apply_weapon_unlocks` will strip any previously-added Kruber entries from `ItemMasterList.bw_sword.can_wield` on next reload. Bardin / wh_priest / Sienna access is unchanged; the `_3p_remap_triggers` and `_weapon_scale_overrides` entries for `bw_sword` are untouched (Bardin still wields it, scale/remap rows were already `dr_`-only).

## 0.12.29-dev (2026-05-16) — Fix `a_unwielded_bow` keep-inventory preview crash on Saltzpyre + longbow; menu labels prefixed with "Melee:" / "Ranged:"

**Crash fix.** `crashify://f210b3b7-ad4f-4e62-b680-9d1e2bc91684` — `[Script Error]: a_unwielded_bow`. Reproed by previewing `es_longbow` on a Saltzpyre career (in this case `wh_bountyhunter`). The v0.12.22 preview swap (`_wt_longbow_preview_swap_apply`) replaced `entry.unit_name` with the empire crossbow 3P unit but left `entry.unit_attachment_node_linking` pointing at the longbow template's table. The longbow's `.unwielded` half references `a_unwielded_bow`, a skeleton node that exists on the empire / elf 3P bodies but NOT on Saltzpyre's. World preview mounts the unwielded (holstered) weapon, calls `Unit.node(saltzpyre_body, "a_unwielded_bow")`, and the engine raises a fatal that bypasses pcall (per `feedback_vt2_unit_node_not_pcall_safe`). Fix: also overwrite `entry.unit_attachment_node_linking` with `Weapons.crossbow_template_1.left_hand_attachment_node_linking.third_person` — the WH crossbow template Saltzpyre uses natively, whose attachment nodes are known to exist on his body. Guarded with a `Weapons.crossbow_template_1` nil check; if the lookup fails we bail before the mesh swap so we don't crash. The in-game `_wt_longbow_3p_swap_apply` already uses `.wielded` (universal hand bone, exists on all 3P bodies) and was unaffected.

**Menu labels.** Prefixed every `melee_*` and `ranged_*` group label in `_localization.lua` with `Melee: ` / `Ranged: ` so the navigation chain reads `Melee: Kruber` → `Melee: Mercenary` (and same for `Ranged: …`). Leaf weapon checkboxes keep their existing `<Character>: <Weapon>` labels. Pure localization-string change, no widget-tree or code change.

## 0.12.28-dev (2026-05-15) — Fix Kerillian native elf-spear 3P animations

`_3p_remap_triggers.to_spear` was missing a `we_` entry, so when Kerillian wielded her own elf spear, `_resolve_3p_remap` fell through to `_default = _3p_remap_spear_to_polearm`. That table was authored for **Kruber wielding the elf spear** (mapping elf-spear attack events to Kruber's polearm-skeleton equivalents) and breaks Kerillian's down_left / left attacks when applied to her own skeleton. Symptom: messed up 3P spear animations on every Kerillian career, visible on bots / other players. Fix: added `we_ = false` to declare "Kerillian native, no remap", mirroring the existing `wh_ = false` pattern on `to_2h_billhook`. One-line data fix; no behavior change for cross-character spear wielders (Kruber/Saltzpyre still get their respective remaps).

## 0.12.27-dev (2026-05-15) — Rename `/status` → `/info` to clear command-name collision

Startup log was showing `[MOD][wt][ERROR] (command): command name 'status' is already used by another mod 'SpawnTweaks'`. SpawnTweaks loads first and owns the global `status` command name — VMF rejects our duplicate registration, leaving `/status` non-functional. Renamed our debug-state command to `info`. Same handler body; new invocation is `/info`. (Reminder: VT2 chat commands are typed as `/<registered-name>` directly — no mod-id prefix.)

## 0.12.26-dev (2026-05-12) — Authentic Brace: final secondary-spread tune, 12× → 9×

`_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT` dialled back from 12.0 to **9.0** per user feel-test ("9× and I think that'll do"). Primary spread stays at 3×, so secondary is now exactly 3× the primary multiplier (was 4× in v0.12.21–v0.12.25). The doc-block step (5) reference value updated to match. No other authentic-brace behavior changes — speed, reticle reticle-jump fix, ammo, reload, damage all unchanged.

## 0.12.25-dev (2026-05-12) — Fix end-of-mission parade crash + consolidate duplicate hooks

**End-of-mission parade crash** (crashify://811e5718-2e04-4995-8a22-0880c44cf44d): `team_previewer.lua:120: attempt to index local 'item_template' (a nil value)`. Triggered when a player has a `character_weapon_variants` cross-character variant in their loadout — CWV variants inherit `entry.name` from the base weapon (per `feedback_cwv_clone_name_clobber.md`), so the level-end verifier looks up the BASE `ItemMasterList` entry whose `can_wield` doesn't include the new career → `BackendInterfaceCommon.can_wield(career, item_data)` returns false → vanilla `LevelEndView._verify_weapon_data` hits a bailout path that assigns `verified_weapon.item_name = career_settings.preview_items[1]`. But `career_settings.preview_items[1]` is now `{ item_name = "..." }` (a table), not a string — Fatshark changed the shape of `preview_items` without updating this bailout path. `team_previewer.cb_hero_unit_spawned_skin_preview` then does `ItemMasterList[that-table]` → crash. Fix: post-hook `LevelEndView._verify_weapon_data` to unwrap the table-shape to its inner `.item_name` string, or clear to nil if unexpected. Reproduced with the user having `we_javelin` (cwv_es_javelin → base we_javelin name) on `es_huntsman`.

**Duplicate-hook warning consolidation** (per memory `feedback_vmf_hook_safe_no_chain` and the user's request):

- `mod:hook("GearUtils", "spawn_inventory_unit", ...)` was registered twice (brace pistols → repeater swap and longbow → crossbow swap). VMF chained these correctly but logged `(hook): Attempting to rehook active hook [spawn_inventory_unit]` each game load. Consolidated: the longbow swap body is now a local helper `_wt_longbow_3p_swap_apply` called from the brace hook's dispatch block. Forward-declared per `feedback_lua_forward_reference`.

- `mod:hook_safe("MenuWorldPreviewer", "equip_item", ...)` was registered THREE times (brace preview swap, longbow preview swap, item-key capture for `_spawn_item_unit` lookup). VMF's `hook_safe` does NOT chain duplicates from the same mod — only the LAST registration actually fired, so the brace preview swap and longbow preview swap were silently dead since they were registered. Consolidated all three into one hook_safe that calls two local helpers (`_wt_capture_preview_item_key`, `_wt_longbow_preview_swap_apply`) followed by the inline brace swap. Forward-declared both helpers. Two fixed bugs as a side effect: brace pistols and longbow now show the swapped 3P mesh in the keep inventory previewer again (they didn't on v0.12.24).

**Files changed:**
- `weapon_tweaker.lua` — version bump, vanilla-bug-fix hook for `LevelEndView._verify_weapon_data` at end of file, two forward declarations + closure-helper conversions for the consolidated hook registrations.

## 0.12.24-dev (2026-05-12) — Pre-resolve per-career `item_units` (fix CW bot crash on bw_ghost_scythe — second attempt)

**Why a second attempt:** v0.12.23 added a `career_name` fallback recovered from `unit_3p`'s `inventory_system._career_name`. The fallback's `mod:warning` log line never fired in the second crash repro (cbcace55), confirming `career_name` was already non-nil at our hook entry. The hook chain still dropped it somewhere between our wrapper (crash-dump frame [12] shows `career_name = "bw_unchained"`) and the unwrapped `gear_utils.create_equipment` (frame [10] shows `nil`). Mechanism unknown — static inspection of the three hook frames (CWV, cosmetics_tweaker, weapon_tweaker) shows clean varargs pass-through.

**Workaround:** instead of trying to fix the lost arg, sidestep the broken path. Vanilla `gear_utils.create_equipment` does `item_units = override_item_units or BackendUtils.get_item_units(item_data, nil, nil, career_name)` — so if we **pre-resolve** `item_units` ourselves (calling `BackendUtils.get_item_units` with the real `career_name`) and pass the result as `override_item_units`, gear_utils uses our version verbatim and never enters the chain-broken code path.

**Gating:** only fires when `item_data` has `right_hand_unit_override[career_name]` or `left_hand_unit_override[career_name]`. Covers the entire Sienna scythe family (`bw_ghost_scythe` / `_magic_01` and their skins) plus any other vanilla weapon with per-career unit overrides. The v0.12.23 `career_name` recovery from `inventory_system` is kept (now feeds this pre-resolve block when arrival is nil).

**Files changed:**
- `weapon_tweaker.lua` — version bump, added pre-resolve `override_item_units` block to the `create_equipment` hook (≈12 lines).

## 0.12.23-dev (2026-05-12) — Recover lost career_name in `create_equipment` (fix CW bot crash on bw_ghost_scythe)

**Crash:** Chaos Wastes mission start, bot Sienna *Unchained* (`bw_unchained`) spawning with `bw_ghost_scythe` in `slot_melee` — engine fatal `Unit not found #ID[877616b4d5c71f36]` (= `units/weapons/player/wpn_bw_ghost_scythe_01/wpn_bw_ghost_scythe_01_3p`, the Necromancer base mesh) inside `world.spawn_unit`. crashify://77917479-d053-4d34-b6b9-629878a7e6ec.

**Cause:** Vanilla `ItemMasterList.bw_ghost_scythe.right_hand_unit_override.bw_unchained = "..._fire"` should redirect Unchained to the `_fire` variant; the package preloader correctly force-loaded `wpn_bw_ghost_scythe_01_fire_3p` for the bot. But at equip time `BackendUtils.get_item_units` returned the BASE unit because `career_name` was `nil` when `gear_utils.create_equipment` called it (the override block at `backend_utils.lua:159-162` is gated on `career_name`). Crash-dump locals show `career_name = "bw_unchained"` at every modded hook frame (`weapon_tweaker:1313`, `cosmetics_tweaker:2542`, `character_weapon_variants:8488`) yet `nil` at the unwrapped `gear_utils.create_equipment` entry — so the hook chain dropped the arg somewhere on the way down to the original. Engine asserts in `world.spawn_unit` bypass pcall (`feedback_vt2_unit_node_not_pcall_safe.md`), so the existing pcall guard didn't help.

**Fix:** In our `GearUtils.create_equipment` hook, if `career_name` arrives nil but `unit_3p` has an `inventory_system` extension, read `_career_name` from it and pass that to `func`. `SimpleInventoryExtension.init` sets `_career_name` before `extensions_ready` fires our hook (`feedback_vt2_mission_spawn_career_lookup.md`), so this is always populated for player/bot mission spawns. 4 lines, weapon-agnostic — protects every weapon that uses per-career `right_hand_unit_override` (the Sienna scythe family + any future ones).

A `mod:warning` on the fallback path will surface other call sites that hit this so we can root-cause the chain pass-through bug separately.

**Files changed:**
- `weapon_tweaker.lua` — version bump, fallback block inside `create_equipment` hook.

## 0.12.22-dev (2026-05-12) — Kruber's Longbow on Saltzpyre with crossbow 3P visuals

New cross-character feature, mirrors the `wh_brace_of_pistols` → repeater pattern from v0.12.2-v0.12.17 but in the opposite direction (Kruber-weapon on Saltzpyre) and with one new wrinkle (LEFT-hand swap + ammo unit swap).

**End-user behavior:**
- Per-career VMF checkboxes for `wh_captain`, `wh_bountyhunter`, `wh_zealot`, `wh_priest` ("Kruber: Longbow", default OFF). Toggle ON to make `es_longbow` equippable on that Saltzpyre career.
- 1P (the player's first-person view): Saltzpyre wields a longbow, fires arrows. Vanilla longbow gameplay — same actions, same damage, same anim events. Per the universal-1P rule (`feedback_1p_animations_universal`).
- 3P (other players' view of Saltzpyre, AND the keep inventory character preview): Saltzpyre appears to wield Saltzpyre's **crossbow** with a **bolt** loaded, playing the crossbow wield + fire 3P animations.

**Implementation (`scripts/mods/weapon_tweaker/weapon_tweaker.lua`):**
- `weapon_unlock_map`: appended `"es_longbow"` to all 4 Saltzpyre career entries.
- `_force_load_sp_crossbow_3p_units()` at mod init: force-loads `wpn_empire_crossbow_tier1_3p` (the crossbow 3P weapon) and `wpn_crossbow_bolt_3p` (the bolt 3P ammo) under references `wt_sp_crossbow_3p` / `wt_sp_crossbow_bolt_3p`. Same async-load pattern the brace-repeater uses.
- `_patch_longbow_empire_template_for_saltzpyre()` at mod init: patches `Weapons.longbow_empire_template` in place — sets `wield_anim_career_3p[wh_*] = "to_crossbow"` (3P wield SM transition) and per-action `anim_event_3p` remaps for events the crossbow 3P SM doesn't author identically: `attack_shoot_fast → attack_shoot`, `attack_shoot_fast_last → attack_shoot_last`, `draw_bow → to_zoom`. Per-career keying means Kruber/Kerillian native wielders see no change.
- New `mod:hook("GearUtils", "spawn_inventory_unit", ...)` parallel to the brace hook. Gates on `item_data.name == "es_longbow"`, `hand == "left"`, career-starts-with-`wh_`. Swaps v_w3p (bow 3P → crossbow 3P) via `Managers.state.unit_spawner:spawn_local_unit_with_extensions` and v_a3p (arrow 3P → bolt 3P) via `GearUtils._attach_ammo_unit`. The bolt attaches using the CROSSBOW template's `ammo_data.ammo_unit_attachment_node_linking.third_person.wielded` (NOT the longbow's arrow linking) so the bolt mounts at the crossbow's nock position. 1P returns left untouched. Full pcall wrap — any failure falls back to vanilla bow/arrow.
- New `mod:hook_safe("MenuWorldPreviewer", "equip_item", ...)` parallel to the brace preview hook. Mutates `info.spawn_data` left_hand entry's `unit_name` → crossbow 3P. No ammo swap in preview (vanilla preview doesn't spawn the bow's arrow). Hooks `MenuWorldPreviewer`, NOT `HeroPreviewer`, per `feedback_inventory_preview_hook_menuworldpreviewer` (the v0.12.17 lesson).

**Files changed:**
- `weapon_tweaker.lua` — version bump, unlock_map (4 lines), force-load block, template patcher, in-game spawn hook, preview hook.
- `weapon_tweaker_data.lua` — 4 new VMF checkboxes (one per Saltzpyre career), all default false.
- `weapon_tweaker_localization.lua` — 4 new "Kruber: Longbow" strings, slotted alphabetically among the existing "Kruber: *" entries.

**Career detection:** uses the v0.12.17 `_unit_career_name` (inventory-extension-first, `Managers.player` fallback) — handles mission-spawn timing correctly. No new helper needed.

**Verification matrix (please test):**
1. Enable `unlock_wh_zealot_es_longbow` (or any career), equip `es_longbow` on that Saltzpyre career.
2. Keep inventory preview: Saltzpyre's preview model holds a crossbow (no visible bolt — preview doesn't render ammo on bows). ✅ if crossbow mesh.
3. Load into a mission: Saltzpyre's 3P body (third-person camera, or another player's view) shows him holding a crossbow with a bolt loaded, playing crossbow wield + fire animations. ✅ if crossbow + bolt + crossbow anims.
4. First-person view in-game: Saltzpyre's 1P shows a longbow + arrow, fires with longbow draw animation, full longbow gameplay (damage profile = arrow_carbine, charge mechanic etc.). ✅ if 1P unchanged from vanilla longbow.
5. Other Saltzpyre career equipping the option: same as above. Try `wh_priest` (notable because it has no native ranged weapon).

**If this does NOT work, here's what to check next, in order:**
- **Crash on equip "Unit not found":** the force-load failed. Look for `[wt sp-longbow-crossbow] force-loaded` in startup log. If absent, the unit paths might be wrong — verify `wpn_empire_crossbow_tier1_3p` and `wpn_crossbow_bolt_3p` resolve. The crossbow unit path was sourced from `wh_crossbow.left_hand_unit + "_3p"` and the bolt from `wh_crossbow.ammo_unit + "_3p"`; if vanilla relies on different package keys for these (unlikely — same code path the brace-repeater uses successfully), use [[reference_vt2_bundle_unpacker]] to brute-hash candidate paths.
- **Bow still showing in 3P:** check log for `[wt sp-longbow-crossbow] swapped`. If absent, the hook isn't firing — confirm career_name resolution (see `feedback_vt2_mission_spawn_career_lookup`). If hook fires but bow still showing, package readiness check might be failing — early return on line 2150ish — temporarily log `Managers.package:has_loaded(_SP_CROSSBOW_3P_UNIT, "wt_sp_crossbow_3p")` to confirm.
- **Crossbow rendered but bolt missing / wrong position:** check log for `arrow→bolt(true)` vs `arrow→bolt(false)`. False means `crossbow_template_1.ammo_data.ammo_unit_attachment_node_linking` was nil — global `Weapons` table might not be loaded at mod init yet. Late-bind by deferring the bolt-linking lookup into the swap pcall body (already done — it reads `Weapons` at swap time, not at module load), but if it's still nil there, try `AttachmentNodeLinking.bolt` directly.
- **Wrong 3P anim:** longbow's per-action `anim_event_3p` overrides might not be enough. Check log for which events fire via the existing `/animlog` command. Saltzpyre's 3P crossbow SM has event names from `Vermintide-2-Source-Code` skeleton dumps — see `reference_3p_skeleton_events`. If the wield is wrong, try `to_crossbow_loaded` instead of `to_crossbow` in `_SP_LONGBOW_CROSSBOW_WIELD_3P`.
- **Keep inventory preview unchanged but in-mission works:** identical class-hook trap to v0.12.16; verify the preview hook is registered on `MenuWorldPreviewer`, not `HeroPreviewer`. (Source check: line containing `if item_name ~= "es_longbow" then return end` should be immediately under `mod:hook_safe("MenuWorldPreviewer", "equip_item", ...)`.)
- **In-mission revert (works in keep, breaks on mission load):** same class as v0.12.16 bug #2 — would mean `_unit_career_name` returned nil. v0.12.17 fix should prevent this; if it still happens, see `feedback_vt2_mission_spawn_career_lookup` fallback notes (try `career_system:career_name()` instead).

**Doc updates:** none beyond this CHANGELOG entry. The patterns this feature uses (MenuWorldPreviewer hook, inventory-extension-first career lookup, force-load pattern, base-template wield_anim_career_3p) are already documented in CLAUDE.md / DEVELOPMENT.md / the four memory entries created in v0.12.17. This release is the second user of those patterns — they now have two reference call sites.

## 0.12.21-dev (2026-05-12) — Authentic Brace: reticle jumps to wide on RMB, secondary speed back to vanilla, secondary spread 16×→12×

Three related changes from user feel-testing v0.12.20.

**Reticle two-step jump fixed** — the user observed the crosshair "unnaturally going from small to large" when entering rapid fire. Root cause: vanilla brace sets `spread_template_override = "pistol_special"` on BOTH `action_two.default` (the RMB lock-target / aim action) AND `action_one.fast_shot` (the rapid-fire shot). v0.12.19's spread-clone patch only walked `action_one.[default|fast_shot|special_action_shoot]` and rewrote their overrides to our wider clone; `action_two.default` was missed, so its override still pointed at vanilla `pistol_special` (max_pitch≈1.0). Result was a two-stage reticle expansion: RMB press → reticle jumps to vanilla pistol_special width, then LMB press → action_one.fast_shot triggers, reticle jumps again to the much wider clone.
- Fix: extended the override-rewrite to walk EVERY action of the template (`for _, sub_actions in pairs(tpl.actions)`), not just `action_one`. Any sub-action with `spread_template_override == "pistol_special"` is rewritten to our wider clone. Now `action_two.default` also uses the wider clone, so the moment RMB is pressed, `WeaponSpreadExtension:override_spread_template()` sets `current_pitch = state_settings.max_pitch` (= 12× the vanilla pistol_special max) and the reticle visually jumps directly to its final wide size with no intermediate stop.
- This matches the behavior the user described — "when the player first takes aim, the reticle should naturally be large to represent the accuracy, like any normal weapon".

**Secondary fire speed back to vanilla** — `_SLOW_MULT` 2.0 → **1.0**. The user said the v0.12.19-v0.12.20 secondary speed ("50% of vanilla") felt too slow and asked to double it. Doubling the speed = halving the duration multiplier = 1.0, which is the no-scaling identity. Practical effect: rapid fire fires at ~4 shots/sec (vanilla cadence) instead of v0.12.19-v0.12.20's ~2 shots/sec. Primary fire / wield / reload still run at 2× speed (`_FAST_MULT = 0.5`), so secondary is now exactly half the speed of primary at vanilla cadence.
- The walker logic that branches on FAST vs SLOW per sub-action / per chain is retained verbatim; with `_SLOW_MULT = 1.0` the "slow" branches are no-ops. Keeping the structure means re-tuning to 1.2 / 1.5 / 2.0 later is a one-line constant change.

**Secondary spread 16× → 12×** — `_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT` dialled back per user feel-test ("16 was too high for inaccuracy"). Primary spread mult stays at 3×. Secondary is now 4× the primary multiplier (was ~5.3× in v0.12.20).

**Files changed:** `scripts/mods/weapon_tweaker/weapon_tweaker.lua`
- Line 24: version bump 0.12.20-dev → 0.12.21-dev.
- `_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT`: 16.0 → 12.0 (comment updated to note action_two.default coverage).
- `_SLOW_MULT`: 2.0 → 1.0 (comment updated; walker structure unchanged).
- Spread-override rewrite loop in step 5: was `for sub_name in ipairs({"default","fast_shot","special_action_shoot"}) do … tpl.actions.action_one[sub_name] …`; now `for _, sub_actions in pairs(tpl.actions) do for _, sub in pairs(sub_actions) do …` — walks every sub-action of every action. New comment explains the two-step reticle jump and why action_two.default needs the rewrite too.
- Doc-block step (2) updated to reference v0.12.19-v0.12.21 history.
- Doc-block step (5) updated: secondary mult value 16.0 → 12.0, mention "applied to EVERY sub-action … incl. action_two.default lock-target" so the reticle behavior is documented.
- Doc-block step (7) updated: speed history (2.0 → 1.0) and the rationale for keeping the split walker structure.
- Info log: re-worded to print the new values and call out the action_two.default coverage.

**Behavior expectations in-game:**
- LMB tap single shot: 2× faster than vanilla, 3× spread. Unchanged from v0.12.20.
- Press RMB (lock-target / aim): reticle jumps directly to the wide secondary size — no two-step expansion, no visible lerp. Spread immediately represents the actual rapid-fire accuracy.
- Hold RMB then LMB → rapid fire: vanilla cadence (~4 shots/sec, was ~2 in v0.12.20), 12× spread (was 16×). Slower than primary, much less accurate than primary, vanilla pacing.
- Reload, mag, damage, ammo unchanged from v0.12.19.

## 0.12.20-dev (2026-05-12) — Authentic Brace: spread tuning pass — primary 4×→3×, secondary 8×→16×

Two-constant tune of the v0.12.19 spread split, per user feel-test. Primary fire is now tighter (single-shot LMB rewards aim more than "spray and pray"), and secondary fire is much sprayer (rapid-fire is now firmly a suppression / point-blank mode, not a substitute for aimed shots).

- `_AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT`: 4.0 → **3.0**. Single-shot LMB (action_one.default → default brace spread clone) is ~25% tighter than v0.12.19.
- `_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT`: 8.0 → **16.0**. Rapid-fire (action_one.fast_shot → pistol_special clone) is 2× wider than v0.12.19, ≈5.3× the primary spread.
- Doc-block reference values in the step (5) commentary updated to match.

No mechanical changes — speed, ammo, damage, reload all unchanged from v0.12.19. Pure number tune.

## 0.12.19-dev (2026-05-12) — Authentic Brace: split primary/secondary fire, restore manual reload (6/12, 1-at-a-time)

User request: differentiate the brace's primary (LMB single-shot) and secondary (RMB-hold rapid-fire) modes. Secondary should be slower AND less accurate than primary; primary keeps its 2× speed and current accuracy. Plus they've changed their mind on reload — bring manual reload back, with a small mag and shot-by-shot loading.

**Speed split (step 7, formerly a uniform 2× speedup):** introduced `_FAST_MULT = 0.5` (2× speed, applied to primary and everything else) and `_SLOW_MULT = 2.0` (50% of vanilla speed, applied to secondary fire). The walker now branches per-sub-action:
- `action_one.fast_shot` sub-action itself: SLOW. `total_time` 1 → 2, `reload_time` 0.1 → 0.2 — the rapid-fire shot's own duration doubles vs vanilla.
- Chain `start_time`s use SLOW when the source sub-action is secondary (so fast_shot's self-loop at `start_time=0.25` becomes 0.5 — rapid-fire cadence drops from ~4 shots/sec to ~2 shots/sec) OR when the chain TARGETS fast_shot (so the RMB-into-rapid-fire chain from `action_two.default` at `start_time=0.25` also becomes 0.5 — entering rapid fire from the lock-target pose takes 2× the vanilla delay).
- Everything else (primary single shot, reload, wield, action_two's hold-pose mechanics, special_action_shoot) keeps the FAST mult — unchanged from v0.12.18 behavior. `0`/`math.huge` still skipped.

**Spread split (step 5, formerly a single `_AUTHENTIC_BRACE_SPREAD_MULT=4.0`):** split into two constants:
- `_AUTHENTIC_BRACE_PRIMARY_SPREAD_MULT = 4.0` — applied to the cloned brace default spread (single-shot LMB). Unchanged from v0.12.15-v0.12.18; primary fire stays at the same "dramatic" accuracy it had before.
- `_AUTHENTIC_BRACE_SECONDARY_SPREAD_MULT = 8.0` — applied to the cloned `pistol_special` spread that `fast_shot` uses via `spread_template_override`. Secondary fire is now 2× more inaccurate than primary. `_wt_clone_spread_wider` gained a `mult` parameter; the two clone callsites pass primary / secondary respectively.

**Reload re-enabled, mag/reserve resized (steps 3 + 4):**
- Step 3 (was: stub `weapon_reload.default.condition_func` / `chain_condition_func` with `_disable_action` to block manual reload): now a no-op. `weapon_reload.default` is left vanilla, so pressing R triggers the normal reload animation. The now-unused `_disable_action` local was deleted.
- Step 4 ammo (was: `clip=12 / per_reload=12 / max=12`, no-reserve, no-per-shot-reload): now `clip=6 / per_reload=1 / max=12`. Mag holds 6, reserve holds 6, each reload animation loads one round; player can keep tapping R to fill the mag round-by-round or interrupt with a shot at any time. Matches a flintlock-pistol-bandolier feel.

**Files changed (one file):** `scripts/mods/weapon_tweaker/weapon_tweaker.lua`
- Line 24: version bump 0.12.18-dev → 0.12.19-dev.
- Lines 1557-1605: doc comment block rewritten (steps 2, 3, 4, 5, 7 all updated to new behavior; step 6 left as historical note).
- Lines 1668-1717: spread mult split into PRIMARY/SECONDARY constants; `_wt_clone_spread_wider` takes a `mult` parameter; the two callsites pass the right one.
- Removed: `_disable_action` local (was only used by the old step 3 manual-reload-disable; no callers left after the step 3 update).
- Step 3 block: now a no-op + explanatory comment (manual reload re-enabled).
- Step 4 block: `ammo_per_clip = 6`, `ammo_per_reload = 1`, `max_ammo = 12`.
- Step 7 block: speed pass rewritten with per-sub-action / per-chain mult selection.
- Info log: now prints primary/secondary spread mults and "primary-speed=2x, secondary-fire-speed=0.5x" separately so the in-game log makes the split visible.

**Behavior expectations in-game:**
- LMB tap single shot: same as v0.12.18 (2× faster than vanilla, 4× spread).
- Hold RMB then LMB → rapid fire: now ~2 shots/sec (vs v0.12.18 ~8 shots/sec; vanilla ~4 shots/sec) with 8× spread — slower than vanilla AND much more inaccurate. Effectively a "spray volley" mode.
- Press R: vanilla manual reload animation runs, loads 1 round. Tap R again, another round, until mag is full or reserve is empty.
- Mag is 6 rounds; full carry is 12.

**No fast_shot chain rewrite** (the v0.12.13 "rewrite every `sub_action == 'fast_shot'` chain to `default`" defense) — keeping the rapid-fire path reachable is now the explicit design intent, since the user wants it to function (just slower and less accurate). Reverted in v0.12.15, not reintroduced here.

## 0.12.18-dev (2026-05-11) — Kruber Longbow on Mercenary and Foot Knight

Added `es_longbow` (Kruber's Empire longbow) to the unlock pool for `es_mercenary` and `es_knight`. Huntsman has it natively; Questing Knight already had it. New checkboxes default to off so existing users see no change until they opt in.

- `weapon_tweaker.lua`: appended `"es_longbow"` to `weapon_unlock_map.es_mercenary` and `weapon_unlock_map.es_knight`.
- `weapon_tweaker_data.lua`: added `unlock_es_mercenary_es_longbow` and `unlock_es_knight_es_longbow` checkboxes in the respective `ranged_*` groups (default `false`).
- `weapon_tweaker_localization.lua`: added the two `"Kruber: Longbow"` strings.

No animation work needed — Mercenary and Foot Knight share Kruber's 3P body skeleton, so the Huntsman longbow event vocabulary applies directly.

## 0.12.17-dev (2026-05-11) — Brace → Repeater swap: fix BOTH preview-path and mission-spawn revert
Two bugs in the v0.12.16-dev attempt. Both fixed here; both produce the same symptom shape (in-game keep model right, somewhere-else wrong) but have different root causes.

**Bug 1 — Inventory preview unchanged.** v0.12.16 hooked `HeroPreviewer.equip_item`. The keep inventory previewer is `MenuWorldPreviewer` (verified: `hero_window_character_preview.lua:171`, `character_selection_view.lua:52`, every `:new(...)` caller of the inventory). VT2's `foundation/scripts/util/class.lua:51-57` COPIES parent methods into the child at class-definition time (no `__index` chain); when `MenuWorldPreviewer = class(MenuWorldPreviewer, HeroPreviewer)` runs at game load, `MenuWorldPreviewer.equip_item` becomes a *static copy* of `HeroPreviewer.equip_item`. VMF `mod:hook("HeroPreviewer", "equip_item", ...)` replaces `HeroPreviewer.equip_item` with a wrapper, but `MenuWorldPreviewer.equip_item` still points at the original unwrapped function — the hook NEVER FIRES on inventory previewer instances. v0.12.16's inline comment claiming "the parent hook fires for both" was the misconception that kept tripping past agents.

Fix: changed BOTH `mod:hook_safe("HeroPreviewer", "equip_item", ...)` hooks (the brace-3P-preview swap and the scale-capture pending-key) to `mod:hook_safe("MenuWorldPreviewer", "equip_item", ...)`. Hook body unchanged. Comment rewritten to call out the class-copy trap and cross-link `feedback_vt2_class_hook_derived`.

**Bug 2 — In-mission 3P reverts to vanilla pistols.** v0.12.16's in-game `GearUtils.spawn_inventory_unit` hook detected Kruber via `_unit_career_name(owner_unit_3p)`, which read `Managers.player:owner(unit):career_name()`. At mission spawn, `SimpleInventoryExtension.extensions_ready` calls `add_equipment_by_category` → `add_equipment` → `GearUtils.create_equipment` → our `spawn_inventory_unit` hook. At THAT moment `Managers.player`'s unit→player reverse association has not yet been re-pointed at the freshly-spawned mission player_unit, so `pm:owner(unit) → nil` and the helper returns nil → hook bails on line 1847 → vanilla brace 3P units returned → Kruber holds the brace in-mission. The keep works because the keep avatar is long-associated.

Fix: rewrote `_unit_career_name` to read `_career_name` from the unit's `inventory_system` extension FIRST. That field is set by `SimpleInventoryExtension.init:47` BEFORE `extensions_ready` fires our hook, so it is always populated by the time the hook runs. `Managers.player` retained as fallback for husk / post-spawn lookups.

**Versions changed:** `MOD_VERSION` 0.12.16-dev → 0.12.17-dev.

**Files changed (one file):** `scripts/mods/weapon_tweaker/weapon_tweaker.lua`
- Line 24: version bump
- Lines 841-856: `_unit_career_name` rewritten (inventory-ext-first, Managers.player fallback)
- Lines 1957-1996: brace-preview hook class swapped + comment rewritten
- Lines 2027-2050: scale-capture hook class swapped + comment trimmed

**Verification matrix (please report which still fails):**
1. Equip brace on Kruber in keep → in-keep 3P shows repeater (worked in v0.12.16, should still work).
2. Open inventory at keep → Kruber preview model shows repeater (NEW — bug 1 fix).
3. Load into mission → Kruber's in-mission 3P shows repeater (NEW — bug 2 fix).
4. Other player joins → husk Kruber shows repeater for them (existing path; husks use `simple_husk_inventory_extension` which still routes through the spawn hook — career resolution goes through Managers.player fallback for husks since husk extension key may differ from "inventory_system"; flag if this regresses).

**If this fix does NOT work, here is what to check next, in order:**
- **Check the in-game log** (`mod:info` messages tagged `[wt brace-3p-swap]` and `[wt brace-3p-swap preview]`) — they print career_name and indicate which path was taken. Silence means the hook didn't fire at all. Non-silence with "kept vanilla unit" means a pcall failed inside the swap body.
- **If preview still wrong (bug 1 still present):** add `mod:echo` at the top of the `MenuWorldPreviewer.equip_item` hook to confirm it's firing at all. If it's not, the keep inventory might be using a DIFFERENT class derived from `MenuWorldPreviewer` (e.g. a subclass) that copied AGAIN — hook that one instead. Verify with `local cls = getmetatable(self); print(cls.__name or tostring(cls))` inside the hook.
- **If mission-spawn revert still present (bug 2 still present):** the `_career_name` field on the inventory_system extension might not be named `_career_name` on the active inventory class. Add a printf with `ext._career_name` and `ext.career_name` and `ext.career_extension and ext.career_extension:career_name()` to figure out which field is populated. Alternative source: `ScriptUnit.extension(unit, "career_system"):career_name()` — the career extension is also registered on the player unit before extensions_ready.
- **Husk path (other players' view of Kruber):** husks use `SimpleHuskInventoryExtension` and might register under a different extension key (`simple_husk_inventory` rather than `inventory_system`). If the husk view shows the wrong thing, expand `_unit_career_name`'s primary probe to also try the husk extension key.
- **Package not loaded race:** the in-game swap pcall body explicitly bails (`return v_w3p`) when `Managers.package:has_loaded(_BRACE_REPEATER_3P_UNIT, "wt_brace_repeater_3p")` is false. If mission load loses the reference (it shouldn't — the load is under our mod's reference at module init, no level transition releases that), the swap silently no-ops. Look for the `mod:info("force-loaded repeater 3P unit")` line on startup; absence means the force-load failed.

## 0.12.16-dev (2026-05-11) — Brace → Repeater swap: cover inventory character preview path (SUPERSEDED by 0.12.17-dev — see above for why)
- Fixed: the brace-of-pistols → repeater 3P swap on Kruber didn't apply to the inventory character preview screen — the preview still rendered the brace's two-pistol mesh while in-game 3P (other players' view of your Kruber) correctly showed the Empire repeating handgun. Cause: the v0.1.187 migration hooked `GearUtils.spawn_inventory_unit` for the in-game equip flow (path 1), but `HeroPreviewer` / `MenuWorldPreviewer` use a different code path — they call `World.spawn_unit(world, unit_name)` directly from a precomputed `spawn_data` table built in `HeroPreviewer.equip_item` (path 2, per `CLAUDE.md` "Three Weapon Rendering Paths"). The spawn_inventory_unit hook never fires for the previewer, so the brace mesh shipped through unmodified.
- Fix: new `mod:hook_safe("HeroPreviewer", "equip_item", ...)` post-hook. When the equipped item is `wh_brace_of_pistols` and `self._current_career_name` starts with `es_` (Kruber career), mutate `self._item_info_by_slot[slot_type].spawn_data` before `_spawn_item` reads it:
  - Right-hand entry: rewrite `unit_name` → `_BRACE_REPEATER_3P_UNIT` (the same repeater 3P unit path the in-game hook spawns).
  - Left-hand entry: drop it. Mirrors the existing `show_third_person_inventory` left-pistol-hide hook — the brace's left pistol would otherwise clip through the repeater's body.
- Package readiness is already taken care of: the repeater 3P unit is force-loaded at mod init via `_force_load_brace_repeater_3p_unit()` (Managers.package:load with prioritize=true), so `World.spawn_unit` in the previewer resolves the resource without needing a per-previewer package load.
- MenuWorldPreviewer (the post-WoM inventory previewer) inherits from HeroPreviewer and doesn't define its own `equip_item`, so the parent hook fires for both — same pattern the adjacent scale-pending-key hook relies on.

## 0.12.15-dev (2026-05-10) — Authentic Brace: lean into rapid-fire, dramatic spread, 12-round mag
- Reverted: step 2 (the `action_two.default` mutation that replaced the vanilla lock-target/fast-shot gate with a `kind="aim"` handgun-style zoom) — gone. action_two.default is left untouched. Right-click does the vanilla lock_target + fast_shot rapid-fire chain. Rationale: rapid fire kept surfacing through paths we couldn't fully exorcise (v0.12.10–v0.12.13 chased it through `lookup_data`, the 3P camera tree, the chain rewrite); the user would rather lean in than keep firefighting.
- Reverted: step 6 (the defensive walk that rewrote every `chain.sub_action == "fast_shot"` to `"default"`) — gone. fast_shot's own self-loop is allowed to function as vanilla intended. Combined with the speed-up that's still in step 7, rapid fire is fast.
- Changed: `_AUTHENTIC_BRACE_SPREAD_MULT` 1.087 → **4.0**. Every numeric leaf on the cloned `brace_of_pistols` spread template scales 4× (`max_pitch` / `max_yaw` / `immediate_pitch` / `immediate_yaw` across every stance — still / moving / crouch / zoomed). The result is dramatic spread on every single shot.
- Added: parallel `pistol_special` clone (`wt_authentic_brace_pistol_special_spread`), also 4× scaled. The vanilla `pistol_special` spread is what `action_one.fast_shot` and `action_one.special_action_shoot` use via `spread_template_override` (≈ rapid-fire). Without scaling this one too, the "dramatic" feel only shows on single shots and rapid fire stays at vanilla pistol_special accuracy. Now both modes are equally inaccurate.
- Reverted: ammo cap 8 → 12. Restores the v0.12.6 cap; per user feedback 8 was too strict. `ammo_per_clip = ammo_per_reload = max_ammo = 12`. No-reserve / no-per-shot-reload behavior unchanged.
- Updated: description only on the accuracy bullet — "~8% (spread widened proportionally on all stances)" → "DRAMATICALLY reduced — spread widened 4× on every stance (and on rapid-fire / pistol_special too)". Other bullets left as-is per the literal request, including the now-stale "Right-click (aim down sights / rapid-fire mode) is disabled" line (gameplay is back to vanilla on that path; leave as-is unless asked to revise).

## 0.12.14-dev (2026-05-09) — Authentic Brace: 2x penetration
- Added: `wt_authentic_pistol` damage profile clone now halves `cleave_distribution.attack` and `cleave_distribution.impact` from shot_sniper's vanilla 0.3/0.3 → 0.15/0.15. Each target consumes half the cleave power, so the projectile passes through roughly twice as many enemies. Vanilla shot_sniper penetrates ~3 targets; Authentic Brace shots now penetrate ~6.
- Implementation lives in `_wt_clone_shot_sniper_no_dropoff()` alongside the dropoff-flattening pass — runs once at module init when the toggle is on, registered in `NetworkLookup.damage_profiles` like before. No new network surface area.

## 0.12.13-dev (2026-05-09) — Authentic Brace: kill fast_shot rapid-fire path
- Fixed: holding right-click and clicking after reload (or other action transitions) could put the brace into `action_one.fast_shot`, whose `allowed_chain_actions` self-chain at `start_time = 0.25` — halved to 0.125 by the v0.12.12 2x speed pass, that's ~8 shots/sec rapid-fire. v0.12.10's action_two.default mutation removed the obvious vanilla path (action_two → fast_shot at lines 303/309 of `brace_of_pistols.lua`), but at least one path the user found still reached fast_shot.
- Fix: defensive walk of every sub-action's chain table — any chain entry whose `sub_action == "fast_shot"` is rewritten to `"default"`. Touches fast_shot's own self-loop (lines 132/144 of the brace template), so even if some unaccounted-for path lands the player in fast_shot, the chains exit to single-shot after one shot. Belt-and-suspenders: also rewrites any other action's chains that happen to point at fast_shot. Done as new step (6) in `_apply_authentic_brace_mode`, before the 2x-speed pass (now step 7), so the speed-up sees the fixed chain entries.

## 0.12.12-dev (2026-05-09) — Authentic Brace: hide off-hand pistol, 8-round cap, 2x action speed
- Fixed: in 3P, Kruber's repeater swap left the **left-hand brace pistol** still rendering, clipping through the repeater. The right-hand 3P swap (in `GearUtils.spawn_inventory_unit` hook) only fires for `hand == "right"`. Hooking the spawn for the left hand and hiding it isn't sufficient because `SimpleInventoryExtension.show_third_person_inventory` (`simple_inventory_extension.lua:1014-1075`) flips visibility back to `true` on every wield. New approach: post-hook `show_third_person_inventory` and force `equipment.left_hand_wielded_unit_3p` invisible whenever the wielded item is `wh_brace_of_pistols` and the wielder's career starts with `es_` (Kruber). Mirrors the visibility-group branching vanilla uses so it applies to whichever path the unit was rendered through. Active regardless of the authentic-brace toggle — the left pistol is unwanted on Kruber whether or not the brace is "authenticated".
- Changed: `Authentic Brace of Pistols` ammo cap reduced 12 → 8. `ammo_per_clip = 8`, `ammo_per_reload = 8`, `max_ammo = 8`. Matches the brace's "8 pistols on the bandolier" cosmetic. No-reserve / no-per-shot-reload behavior from v0.12.8 is unchanged.
- Added: 2x action speed when the toggle is ON. Walks `Weapons.brace_of_pistols_template_1.actions[*][*]` and halves `total_time`, `total_time_secondary`, `fire_time`, `minimum_hold_time`, `cooldown`, `reload_time`, and every `allowed_chain_actions[*].start_time`. `0` and `math.huge` are skipped (preserves "instant" and "hold-forever" semantics). Applied last in `_apply_authentic_brace_mode` so the new aim action's fields from step (2) (`minimum_hold_time = 0.3`, `cooldown = 0.3`) get halved too — zoom snaps in/out at 0.15s.

## 0.12.11-dev (2026-05-09) — Fix Authentic Brace zoom crash in 3rd-person mode
- Fixed: right-click aim crashed in 3rd-person mode at `camera_manager.lua:387` (`attempt to index field 'node' (a nil value)`). v0.12.10 set `default_zoom = "first_person_node"` on the aim action. `GenericStatusExtension.set_zooming` (`generic_status_extension.lua:1519`) appends `_third_person` to the camera name when 3P mode is on, producing `"first_person_node_third_person"` — which doesn't exist in the camera tree. `CameraManager.set_camera_node` then constructs `next_node = { node = tree.nodes[node_name] }` with `node = nil` and crashes when it dereferences it later in the function.
- Fix: clear `default_zoom` (set to `nil`). Engine default is `"zoom_in"`, which has both `zoom_in` and `zoom_in_third_person` defined in `camera_settings.lua:18-19` — works in either camera mode. Vanilla Empire handgun also omits this field for the same reason; matching that prior art.
- Compatible with general_tweaker's third-person camera toggle. Right-click in 3P now zooms the over-shoulder camera in just like the handgun does.

## 0.12.10-dev (2026-05-09) — Fix Authentic Brace right-click crash (lookup_data preservation)
- Fixed: right-click on the brace with the toggle ON crashed at `action_utils.lua:834` (`attempt to index field 'lookup_data' (a nil value)` in the user's runtime, line 927 in their build). v0.12.9 replaced `Weapons.brace_of_pistols_template_1.actions.action_two.default` with a freshly-constructed table — but at game load `weapons.lua:312` walks every weapon template and attaches `lookup_data = { item_template_name, action_name, sub_action_name }` to each sub-action. `ActionUtils.resolve_action_selector` dereferences that field on every action transition; a fresh table without it crashed on the first right-click.
- Fix: mutate the existing `action_two.default` table in place instead of replacing it. Strip the dummy/lock-target fields (`anim_event`, `anim_end_event`, `anim_end_event_condition_func`, `spread_template_override`, `buff_data`) and overwrite the rest with the aim-action config. `lookup_data` and any other engine-attached metadata stays attached. End-user behavior identical to the v0.12.9 intent: handgun-style FOV zoom on right-click, no animation.

## 0.12.9-dev (2026-05-09) — Authentic Brace: right-click is now handgun-style zoom (no anim)
- Changed: `action_two.default` is now a clean optical zoom instead of being disabled outright. v0.12.6 left it as a dead `kind="dummy"` (lock-target pose, fast-shot mode) with `condition_func = always_false` to short-circuit it; v0.12.9 replaces it with a fresh `kind="aim"` action that triggers the engine's standard zoom path (`set_zooming(true, default_zoom)` in `action_aim.lua:134`) with `default_zoom = "first_person_node"` — same zoom the Empire handgun uses on right-click.
- No animation: `anim_event` and `anim_end_event` are deliberately omitted. The brace's state machine (`dual_pistol`) doesn't have `to_zoom`/`to_unzoom` events so any anim would be a missing-event warning anyway, and the user wanted "no ADS animation, just a zoom" specifically. The shoulder stays at hip; the camera FOV tightens.
- Chain actions: while zoomed, `action_one` (left-click) still fires the regular shot, `weapon_reload` and `action_wield` still chain — same set the handgun exposes. `fast_shot` and the lock-target pose are unreachable now (action_two no longer leads to them).
- `condition_func` mirrors the handgun: aim is denied if `total_remaining_ammo <= 0`, so an empty brace can't pretend to zoom. `unzoom_condition_function` follows the standard "don't unzoom on interrupting action" idiom.
- `_disable_action` (the always-false sentinel) is still in use for `weapon_reload.default` — only the action_two patch path changed.

## 0.12.8-dev (2026-05-09) — Authentic Brace: no reload animation between shots
- Changed: with `Authentic Brace of Pistols` ON, ammo is now `ammo_per_clip = 12 / ammo_per_reload = 12 / max_ammo = 12` instead of `1 / 1 / 12`. The whole 12-round pool lives in the clip, reserve is zero. Player clicks → fires → clicks → fires straight through 12 shots with no reload animation between any of them.
- How it works: `weapon_reload.auto_reload.condition_func` (`brace_of_pistols.lua:475`) returns `ammo_count() == 0 AND can_reload()`. With clip == max_ammo, the clip is non-empty until the very last shot, so the auto-reload chain — still wired in `action_one.default.allowed_chain_actions` — never gates true and the animation never plays. After the 12th shot, `can_reload()` is also false (reserve=0), so even the empty-click moment doesn't trigger an animation. Effectively the brace becomes a 12-round magazine that just runs out when empty (until ammo pickup).
- Trade-off: starting reserve goes from 11 to 0. Total ammo capacity is unchanged at 12 — you're still firing the same number of shots per ammo refill, just with all of them immediately accessible instead of staged through a chamber.

## 0.12.7-dev (2026-05-09) — Authentic Brace damage profile NetworkLookup fix
- Fixed: `Authentic Brace of Pistols` toggle silently did nothing in v0.12.6. The cloned damage profile `wt_authentic_pistol` was added to `DamageProfileTemplates` but never registered in `NetworkLookup.damage_profiles`. That lookup is built once at game-load (`network_lookup.lua:2203`) and frozen with an `__index` metatable that errors on unknown keys (`:2356`); `PlayerProjectileUnitExtension._init` (`:92`) does `NetworkLookup.damage_profiles[impact_data.damage_profile]` at every projectile spawn, so every brace shot threw and the firing path bailed out before any damage was applied — making the entire toggle invisible in-game.
- Fix: mirror the CWV pattern (`character_weapon_variants.lua:1364`) — after inserting the clone into `DamageProfileTemplates`, also `rawset` the key into `NetworkLookup.damage_profiles` at both `#tbl+1` (numeric → string) and `[key]` (string → numeric) so projectile spawn finds a valid network ID.
- Spread template clone (`wt_authentic_brace_of_pistols_spread`) didn't need the same treatment — `SpreadTemplates` isn't in `NetworkLookup` and is read by-reference at fire time.
- All other v0.12.6 patches (ammo_data clip/reload/max, `weapon_reload.default` condition_funcs, `action_two.default` ADS gate, `ignore_shield_hit` per sub-action) were already applying correctly; only the damage-profile path was broken.

## 0.12.6-dev (2026-05-09) — Authentic Brace of Pistols toggle
- Added: new `Weapon Overrides → Authentic Brace of Pistols` VMF setting (default OFF). When ON, patches `Weapons.brace_of_pistols_template_1` in place at mod init with five behavior changes that turn the brace into a flintlock-style single-shot pistol:
  - **Damage**: every firing sub-action's `impact_data.damage_profile` switches from `shot_carbine` to `wt_authentic_pistol` (a clone of Kruber's handgun's `shot_sniper` with the near→far dropoff flattened — full damage at all ranges). Plus `ignore_shield_hit = true` on the firing sub-actions, mirroring the handgun's shield-break behavior.
  - **No ADS / rapid-fire**: `action_two.default.condition_func` returns false, so right-click no longer enters lock-target mode. The `fast_shot` chain it gates is unreachable, leaving only the single-shot left-click.
  - **No manual reload**: `weapon_reload.default` `condition_func` and `chain_condition_func` both return false. The `auto_reload` chain (`auto_chain = true`) still fires automatically from action_one and refills the chamber after each shot — same pattern as throwing axes / bows.
  - **Ammo**: `ammo_per_clip = 1`, `ammo_per_reload = 1`, `max_ammo = 12` (vanilla: clip 12 / reload 2 / max 30). One shot in the chamber, auto-loads the next from a 12-round reserve.
  - **Spread**: `default_spread_template` switches to `wt_authentic_brace_of_pistols_spread`, a clone of `SpreadTemplates.brace_of_pistols` with every `max_pitch` / `max_yaw` / `immediate_pitch` / `immediate_yaw` scaled by 1.087 (~8% wider = ~8% less accurate). Recursive scale walk handles the nested `continuous` / `immediate` / per-stance leaves.
- Toggle requires a restart to apply or revert — the patches are applied in place to the global `Weapons.brace_of_pistols_template_1` and there's no snapshot of vanilla state to restore from.
- Affects every wielder of the brace (Saltzpyre native + Kruber via WT cross-access). The 3P unit swap on Kruber is independent of this toggle and continues to work as before.

## 0.12.5-dev (2026-05-09) — Brace of Pistols 3P-swap package fix
- Fixed: Kruber equipping `wh_brace_of_pistols` crashed with `[Script Error]: Unit not found` when the brace-3P-swap hook tried to spawn the Empire repeater rifle 3P unit (crash GUID d9e1d3d3). The repeater unit's per-unit package isn't pre-loaded by the brace's vanilla inventory package — Saltzpyre never needed it because his brace 3P stays the brace, and Kruber's other career packages don't share assets with Saltzpyre's repeater-rifle pool.
- Fix mirrors the CWV Tuskgor-Javelin pattern (`feedback_cwv_cross_character_unit_packages.md`): force-load the repeater 3P unit at WT mod init via `Managers.package:load(unit_path, "wt_brace_repeater_3p", nil, async=true, prioritize=true)`. Stingray treats the unit path as a synthetic per-unit package, same way `PickupPackageLoader` does — by the time any equip flow runs, the resource is loaded and `spawn_local_unit_with_extensions` finds it.
- Defensive guard: the swap hook now checks `Managers.package:has_loaded(_BRACE_REPEATER_3P_UNIT, "wt_brace_repeater_3p")` before attempting the spawn, falling back to vanilla brace 3P unit if the load hasn't completed yet (rare race during very-early equip before the async load lands).

## 0.12.4-dev (2026-05-08) — Adventure trait pool toggles + Chaos Wastes traits
- Added: new collapsible `Weapon Traits (Adventure)` group in the VMF settings with four sub-groups:
  - `Adventure Melee Traits` — checkboxes for the 6 vanilla melee traits (Swift Slaying, Parry, Off Balance, Heroic Intervention, Resourceful Combatant, Opportunist). All default ON.
  - `Adventure Ranged Traits` — checkboxes for the 8 unique vanilla ranged traits across the `ranged_ammo` and `ranged_heat` pools (Inspirational Shot, Scrounger, Conservative Shooter, Resourceful Sharpshooter, Hunter, Barrage, Thermal Equalizer, Heat Sink). All default ON.
  - `Chaos Wastes Melee Traits` — 15 CW traits (Shockwave, Armor Breaker, Shield of Isha, Bloodthirst, Headhunter, Home Run, Shield of Splinters, Serrated Blade, Crescendo Strike, Follow Up, Always Blocking, Big Swing Stagger, Crit Chain Lightning, Collateral Damage, melee Heal on Crit). All default OFF.
  - `Chaos Wastes Ranged Traits` — 5 CW ranged-only traits (Refilling Shot, Piercing Projectile, Extra Shot, Ranged Crit Explosion, Ammo Pickup Reload Speed). All default OFF.
- Mechanism: rewrites `WeaponTraits.combinations[melee/ranged_ammo/ranged_heat/trollhammer_torpedo]` in place to reflect the toggles. Existing CW traits are already in `WeaponTraits.traits` and `BuffTemplates` (merged at game load by `weapon_traits_morris.lua`) — they only failed to appear in adventure crafting because the vanilla pools didn't list them.
- UI gating: the two `Chaos Wastes …` groups are stripped from the widget tree when `crafting_in_modded` is not installed (mirrors the existing `_strip_cwv_widgets` pattern). The runtime always honours stored values regardless of cim presence.
- Lifecycle: trait filters re-apply on `on_setting_changed` (any `trait_*` or `cw_trait_*` id) and on `on_game_state_changed`. `on_disabled` reverts the pools to a snapshot captured on first apply.
- Empty-pool safety: if every toggle in a pool ends up off, the pool falls back to the captured vanilla snapshot rather than leaving cim's reroll with nothing to pick.
- Cross-mod contract: `crafting_in_modded` already reads `WeaponTraits.combinations[trait_table]` dynamically (no hardcoded keys) so weapon_tweaker's mutations propagate automatically. Documented this contract above `_reroll_traits` in `cim/standard_forge.lua` to lock in the design.

## 0.12.3-dev (2026-05-08)
- Wired: `wh_brace_of_pistols` checkbox in `_data.lua` for all 4 Kruber career ranged groups + matching `_localization.lua` labels ("Saltzpyre: Brace of Pistols"). v0.12.2 added the unlock to `weapon_unlock_map` but missed the UI checkbox definitions — without those the unlock UI didn't surface the option, so the user couldn't actually toggle it on. Default OFF (per the existing pattern for cross-character ranged weapons).
- Removed: `unlock_es_*_dr_handgun` checkboxes for all 4 Kruber careers + the `dr_handgun` entry in each Kruber career's `weapon_unlock_map` list + the matching localization entries. Per user — Bardin's Handgun ("rifle") was a cross-character cosmetic curiosity that the user doesn't want surfaced as a Kruber option. Bardin's natives (`dr_ranger`, `dr_ironbreaker`) and the other Bardin careers' lists are unchanged.

## 0.12.2-dev (2026-05-08) — Brace of Pistols on Kruber (migrated from CWV)
- Added: `wh_brace_of_pistols` cross-access on all 4 Kruber careers (`es_mercenary` / `es_huntsman` / `es_knight` / `es_questingknight`) in `weapon_unlock_map`. Kruber can now equip Saltzpyre's brace via the standard wt unlock UI.
- Added: 3P unit swap hook on `GearUtils.spawn_inventory_unit`. When a Kruber career equips `wh_brace_of_pistols`, the brace's 3P body unit is destroyed and replaced with the Empire repeating handgun mesh (`wpn_emp_handgun_repeater_t1_3p`). The 1P side keeps the brace cross-arm fire animation, so the user sees the brace in first-person but other players (and the inventory preview) see Kruber wielding a repeater. Pcall-wrapped: any swap failure returns vanilla units unchanged → equipping never breaks because of this hook.
- Added: base `brace_of_pistols_template_1` patches scoped to Kruber careers — `wield_anim_career_3p` for `es_*` → `to_repeating_handgun` (Kruber's vanilla repeater wield SM), and per-action `anim_event_3p` remap for `special_action` (the brace's fire-all-8-pistols finisher) → `attack_shoot_fast` (closest repeater clip; the special_action event isn't authored on Kruber's repeater SM). Saltzpyre native wielders fall through unchanged.
- Migrated from `character_weapon_variants` v0.1.189 — the previous `cwv_es_brace_repeater` standalone variant + `_cwv_3p_unit_override_swap` infrastructure has been removed from CWV. Same end-user behavior, but lives on the vanilla brace cross-access path now (no separate inventory item).

## 0.12.0-dev (2026-05-05) — Crafting subsystem split out into Crafting in Modded mod
The entire Athanor crafting subsystem (~1800 lines: NetworkLookup patch, forge persistence, Athanor UI hooks, BackendInterfaceWeavesPlayFab redirects, HeroWindowWeaveForgeWeapons hooks, `/forge*` console commands, `/craft_dump` command, `forge_hotkey` keybind) has been moved into a new sibling mod, `crafting_in_modded` (internal ID `cim`). Weapon Tweaker now focuses solely on cross-career weapon unlocks, animation remapping, and scale/offset.

Migration note: weapons crafted under prior versions of `wt` are saved under the `wt` namespace and will not be migrated to `cim`. They are session-only artifacts and will be lost on the upgrade.

## 0.11.20-dev (2026-05-05) — Deduplicate crafting weapon list
- Crafting menu now deduplicates entries by `display_name` — no more duplicate weapons in the list.
- Excluded `promo` rarity items (player's own crafted weapons) from appearing as craft templates.
- Removed `backend_id` lookup from list population (unnecessary for a craft template catalogue).

## 0.11.19-dev (2026-05-05) — Fix startup rehook warnings
- Merged duplicate `HeroPreviewer.equip_item` hook_safe registrations into one (removed dead debug probe).
- Merged duplicate `BackendManagerPlayFab._create_interfaces` hook_safe registrations via forward-declared `_athanor_inject_all`.
- Eliminates two `[WARNING] Attempting to rehook active hook` messages on startup.

## 0.11.18-dev (2026-05-05) — Fix crafted items treated as MIL templates
- Crafted (promo) weapons now inject via `backend_mirror:add_item()` instead of MoreItemsLibrary. Fixes: template-style gray background, blocked cosmetic editing.
- Added `_athanor_inject_item` / `_athanor_inject_all` functions for promo item lifecycle.
- `_forge_inject_all` now skips promo items (handled by Athanor path instead).
- Persistence: `_forge_save` now stores `rarity` and `traits` array.
- Weapon list: cleared "Magic Level" / "1800" power text from craft template entries.
- Added `/craft_dump` diagnostic command for rarity/localization/backend debugging.

## 0.11.17-dev (2026-05-02) — Dual axes: distinct light chain animations
v0.11.15's light remaps collapsed L1, L3, L4 onto the same dual_hammers `attack_swing_left` (L1 swing), making 3 of the 5 lights look identical. Spread them across all 5 dual_hammers light anim_events instead:
- L2 release `attack_swing_right_diagonal` → `attack_swing_left` (dual_hammers L1)
- L3 release `attack_swing_left` → `attack_swing_down` (dual_hammers L2)
- L4 release `attack_swing_right` → `attack_swing_up` (dual_hammers L4)
- L5 release `attack_swing_down` → `attack_swing_stab` (dual_hammers L5)
- L1 release `attack_swing_left_diagonal` left native — plays as dual_hammers L3 swing.

Heavy chain unchanged (user confirmed perfect in v0.11.15).

## 0.11.15-dev (2026-05-01) — Dual axes: per-attack remaps to dual-hammers SM
Animlog from v0.11.13 dr_ranger play showed all attack events firing without `[MISSING]` tags but several producing no visible 3P animation — the dual-hammers SM (loaded by the wield redirect) doesn't have transitions for dual-axe-specific events. Added template-based remaps in `_3p_template_remaps[dual_wield_axes_template_1]` for the 5 problematic events:
- `attack_swing_charge_diagonal` → `attack_swing_charge_left` (L3 + H3 charge windup)
- `attack_swing_heavy_right` → `attack_swing_heavy_right_diagonal` (H1 release)
- `attack_swing_heavy` → `attack_swing_heavy_down` (H2 release)
- `attack_swing_right_diagonal` → `attack_swing_left_diagonal` (L2)
- `attack_swing_right` → `attack_swing_left` (L4)

Per-career entries for `dr_ironbreaker` / `dr_ranger` / `dr_engineer`; `dr_slayer` has no entry so `_resolve_template_remap` returns nil and native dual-axes animations play. Targets are the dual_hammers template's anim_events — `Unit.has_animation_event` was TRUE on the original events too (per memory rule), so visual confirmation is the only test that matters.

## 0.11.13-dev (2026-05-01) — Dual axes on Bardin's non-Slayer careers
- Added `to_dual_axes` → `to_dual_hammers` redirect for non-`dr_slayer` careers. `dr_dual_wield_axes` is already unlocked for Ironbreaker/Ranger/Engineer in `weapon_unlock_map`, but `to_dual_axes` is the Slayer-only wield event — without this redirect, the 3P SM stays in idle on the other Bardin careers and no attack animations play. Mirrors the v0.9.116 pattern used for `to_dual_hammers_priest`. Slayer is unaffected (matches the prefix and skips the redirect). Per-attack remaps may follow once `/animlog` reveals which dual-axe-specific events (`attack_swing_charge_diagonal`, `attack_swing_heavy_right`, `attack_swing_heavy`, `attack_swing_right_diagonal`, `attack_swing_right`) don't animate on the dual-hammers SM.

## 0.11.8-dev (2026-05-01) — Migrated to VMB build pipeline

Moved from the raw Stingray SDK build (`wt.mod`, `settings.ini`, `lua_preprocessor_defines.config`, `.build/OUT/`) to VMB (`weapon_tweaker.mod`, `itemV2.cfg`, `bundleV2/`). Workshop ID `3712896117` and internal mod ID `"wt"` preserved — existing user settings are unaffected. `itemV2.cfg` set to `visibility = "private"`.

Intermediate dev versions 0.11.5–0.11.7 were undocumented in this changelog; treat them as iterative cleanup leading into the VMB migration.

## 0.11.4-dev (2026-05-01) — Crafted items: promo rarity (purple icon background)
- **Crafted items now use `"promo"` rarity** — purple icon background (`icon_bg_promo`). Patches `NetworkLookup.rarities` at mod init to add `"promo"` entry, preventing the `NetworkLookup.lua` crash on equip (v0.11.3 used `"promo"` without the lookup patch → crash on re-equip).

## 0.11.3-dev (2026-04-30) — Crafted items: promo rarity attempt (BROKEN)
- Set crafted item rarity to `"promo"` for purple background. **Crashed** on equip: `NetworkLookup.rarities` doesn't contain `"promo"`. Reverted in 0.11.4.

## 0.11.2-dev (2026-04-30) — Mod Weapon Crafting: live property/trait apply
- **Bubble grid changes now apply to the real item.** Added `_forge_apply_to_item()` — converts weave-format properties (slot indices → float values) and traits (weave keys → regular keys) back to the backend item on every set/remove. Also updates `CustomData` JSON for persistence within the session.

## 0.11.1-dev (2026-04-30) — Mod Weapon Crafting: property slot overlap fix
- **Fixed bubble grid slot collision.** Property slot indices now assigned sequentially across all properties (property 1 → slots {1,2,...}, property 2 → slots {N+1,...}) instead of both starting from slot 1. Prevents properties from overriding each other in the weave forge grid.

## 0.11.0-dev (2026-04-30) — Mod Weapon Crafting: item creation system
- **Client-side item crafting.** "Choose Weapon" now shows ALL career weapons (not weave templates). Selecting a weapon and clicking "CRAFT" creates a new item via `backend_mirror:add_item()` with `Application.guid()` backend IDs, power 300, exotic rarity.
- **Hooked 5 methods on `HeroWindowWeaveForgeWeapons`:** `_present_item` (no locked state), `_set_presentation_locked_state` (never locked), `_update_equip_button_status` (CRAFT label), `_on_list_index_selected` (always enable craft), `_equip_item` (create + equip item).
- Crafted items are session-only — lost on game restart (PlayFab resync).

## 0.10.42–0.10.47-dev (2026-04-30) — Forge UI: panel positioning polish
- Iterated icon and text positioning within overview/properties/trait panels. Final offsets: overview Y=740 (icon internal Y=-20), properties Y=500 (option text nudged -10), trait Y=310.

## 0.10.34–0.10.41-dev (2026-04-30) — Forge UI: item detail panels on hover, viewport polish
- **Item detail panels on hover.** Hovering melee (viewport 1) or ranged (viewport 3) shows the weapon's overview, properties, and trait panels in the center viewport 2 area — uses `UIWidgets.create_item_option_overview/properties/trait` factory widgets initialized via `UIWidget.init()`.
- **Viewport 2 (amulet) hidden** — unused in mod forge, all viewport 2 widgets set to `content.visible = false`.
- **Hover highlight color** changed from white to grey (123, 123, 123 RGB).
- **Panel positioning** iterated across multiple versions to align icon, properties, and trait vertically (final offsets: overview Y=630, properties Y=470, trait Y=320).

## 0.10.33-dev (2026-04-30) — Forge UI: hover highlights to white, cluster glow recolor
- Overview viewport hover highlights (`viewport_button_highlight_`, `viewport_button_text_highlight_`) recolored from purple to white.
- Properties sub-menu `cluster_background_effect_1` recolored from purple to deep red.

## 0.10.32-dev (2026-04-30) — Forge UI: enhanced forge_dump_props diagnostics
- `forge_dump_props` command now reports preview state (`_viewport_widget`, `_item_previewer`, `_previewer_initialized`) and property/trait key mapping results for debugging the properties sub-menu.

## 0.10.31-dev (2026-04-30) — Forge UI: properties sub-menu power fix, additional widget hiding
- Properties sub-menu power display now reads from `params.selected_item.backend_id` (was nil via `_item_backend_id`). Shows real weapon power instead of spoofed 1800.
- Additional widget hiding in properties layout: level title/value, mastery, upgrade button, wheel rings.

## 0.10.30-dev (2026-04-30) — Forge UI: forge_dump_props diagnostic command
- Added `/forge_dump_props` command using `mod:echo` (always flushes) instead of `mod:info`. Dumps properties window widgets, `params.selected_item`, and property/trait key mapping results.

## 0.10.15–0.10.29-dev (2026-04-29–30) — Mod Weapon Crafting forge UI
### Added
- **Athanor forge repurposed as Mod Weapon Crafting UI.** Opens via B hotkey. Backend hooks (`BackendInterfaceWeavesPlayFab`) intercept all weave loadout queries to serve real equipped weapon data.
- **Property/trait pre-fill from real items.** `_forge_seed_item()` reads equipped weapon's `.properties` and `.traits`, maps regular keys to weave-prefixed keys (`crit_boost` → `weave_crit_boost`), and converts float values to bubble-slot arrays. Seed persists across edits so adding/removing properties doesn't discard existing data.
- **`/forge_dump` command** for traversing forge UI widget hierarchy (`ingame_ui.views[current_view]._machine._state._active_windows`).

### Changed
- **Header rebranded**: "Weave Power" label replaced with "MOD WEAPON CRAFTING" in large white text.
- **Background recolored**: Bottom smoke/ember effects changed from amber/purple to deep red (`bottom_glow_smoke_1/2/3`, `bottom_glow_embers_1`). Top fog layer (`top_glow_smoke_1`) recolored to match.
- **Power displays fixed**: Overview viewports show real weapon power levels. "Level: 999" labels hidden across overview and properties layouts.

### Removed (hidden)
- Forge level display, Athanor essence counter/icon, upgrade button, mastery counter/title/icon, wheel/ring background decorations — all set to `content.visible = false` when custom forge is active.

## 0.10.29-dev (2026-04-30) — Remove on_reload package clearing
### Fixed
- **`on_reload` package clearing caused locked resource crash.** Clearing `loaded_packages = {}` on our mods prevented the engine's `unload_mod` from calling `release_resource_package` on those handles — the resources stayed locked in the resource manager. When the engine then tried to unload a subsequent mod whose package shared or referenced those resources, it hit `ensure_unlocked` and crashed with *"Unloading a locked resource, lock count: 1"*. The `on_reload` hack was originally added to prevent VMF atlas crashes during `/reload`, but that's now handled properly by cosmetics_tweaker's `VMFOptionsView.update` pre-check guard. Removed the package clearing entirely; `on_reload` is now a no-op.

## 0.10.28-dev (2026-04-29) — Match human-readable mod names in OURS lookup
### Fixed
- **Scoped `on_reload` matched zero mods.** v0.10.26 used `m.name = "wt"` etc. as the key into `OURS`, but `mod_manager.lua` sets `mod.name` to the human-readable Workshop title (`"Weapon Tweaker"`, `"Cosmetics Tweaker"`...). The check missed every tweaker mod, so `on_reload` cleared zero packages — defeating the purpose. Symptom: `[WT] on_reload DONE (cleared packages on 0 tweaker mods of 72 total)` followed by *"Unloading a locked resource #ID[ddcb1a7c], lock count: 48"* crash. Fix: switched the `OURS` keys to the actual `m.name` values.

## 0.10.26-dev (2026-04-29) — Scope on_reload package clear to our mods only
### Fixed
- **`on_reload` was nuking third-party atlases.** `wt.mod`'s `on_reload` cleared `loaded_packages` on all 72 installed mods, not just our tweakers. After every `/reload`, VMF's `vmf_atlas`, Loremaster's Armoury's `armoury_atlas` / `la_notification_icon`, and any other mod's atlas got their package handles wiped. The materials stayed in GPU memory until *something* did a name lookup — at which point the engine fataled with `Material 'X' not found in Gui`. Symptoms cascaded across UI surfaces: NewsFeedUI, VMF options view, world markers, inventory exit. Fix: scope the package clear to a known set (`wt`, `ct`, `gt`, `crt`, `t`, `cosmetics_tweaker`) and leave every other mod alone.

## 0.10.11-dev (2026-04-29) — Remove stale forge draw hooks
### Fixed
- **Mod load errors**: Four `mod:hook_safe` calls targeting `HeroWindowWeaveForgeOverview.draw`, `HeroWindowWeaveForgePanel.draw`, `HeroWindowWeaveForgeBackground.draw`, `HeroWindowWeaveProperties.draw` failed at startup — Fatshark removed the `draw` methods on these classes in a prior patch. The hooks were debug instrumentation for the defunct `forge_dump` command. Removed.

## 0.10.21-dev (2026-04-29) — Kerillian spear+shield H2 fix
- Removed erroneous `attack_swing_heavy_down_right` → `attack_swing_heavy_down` from `_3p_remap_deus_to_spear_shield`. The elf's native spear+shield SM uses `attack_swing_heavy_down_right` for its own H2 release — the remap was overriding a natively-working event with one that produces no animation.

## 0.10.20-dev (2026-04-29) — Kerillian greatsword grip tuning
- Z-offset for `es_2h_sword` and `wh_2h_sword` on `we_*` set to `{0, 0, -0.12}` — `-0.25` was overcorrection, `-0.07` was imperceptible.

## 0.10.19-dev (2026-04-29) — Kerillian greatsword grip offset (larger)
- Z-offset for `es_2h_sword` and `wh_2h_sword` on `we_*` increased to `{0, 0, -0.25}` — previous `-0.07` was not noticeable.

## 0.10.17-dev (2026-04-29) — Kerillian greatsword push-attack fix
- Push-attack remap corrected: `attack_swing_down_right` → `attack_swing_heavy` (elf greatsword default heavy release). Previous version used `attack_swing_stab` which didn't match.

## 0.10.16-dev (2026-04-29) — Kerillian greatsword remap refinement
- Changed H1 heavy release remap (`attack_swing_heavy_left_diagonal`) from `attack_swing_heavy` to `attack_swing_left` so Kerillian's H1 release visually matches her L1 swing when wielding Kruber's/Saltzpyre's greatsword.
- Added push-attack remap: `attack_swing_down_right` → `attack_swing_stab`. Push-attack was previously unanimated on Kerillian with the human greatsword.

## 0.9.129-dev (2026-04-28) — Inventory preview now respects scale & grip offset
- Added `MenuWorldPreviewer:equip_item` and `MenuWorldPreviewer:_spawn_item_unit` hooks. The new (post-WoM) inventory preview uses MenuWorldPreviewer instead of HeroPreviewer/GearUtils for character display; the existing in-game scale/offset code never reached those preview units. Now we capture the weapon key from `equip_item` (where it's exposed as the first arg) and apply scale/offset to the unit when it's spawned via `_spawn_item_unit` (where item_data is the weapon TEMPLATE, not the inventory item — so the key isn't directly available there). Per-previewer mapping is weak-keyed so it doesn't pin the previewer in memory.

## 0.9.120-dev (2026-04-28) — Bardin's axe on Kerillian X/Y scale
- Added `dr_1h_axe` scale `{0.85, 0.85, 1}` for `we_*` careers — 15% thinner X/Y, length unchanged.

## 0.9.119-dev (2026-04-28) — Crowbill H1/H3 fix on Bardin
- Added `dr_` override to `one_handed_crowbill`. H1 and H3 used to remap to `attack_swing_heavy` which produces no animation on Bardin's crowbill SM; now they use the elf-sword overhead targets (`attack_swing_charge_left_diagonal` + `attack_swing_heavy_down`). H2 unchanged. Other careers' crowbill behavior preserved via `_default`.

## 0.9.118-dev (2026-04-28) — Bardin grip on Saltzpyre's dual hammers
- Z-offset `{0, 0, 0.15}` for `wh_dual_hammer` on `dr_*`.

## 0.9.116-dev (2026-04-28) — wh_dual_hammer wield-event redirect
- Added `to_dual_hammers_priest` → `to_dual_hammers` redirect for non-Saltzpyre careers. Saltzpyre's dual hammers fire `to_dual_hammers_priest` on wield; this event is missing on Bardin's skeleton, leaving the SM in idle and producing no 3P attack animations. Redirecting to Bardin's native dual-hammers wield event loads his working SM, and since both weapons fire the same chain events, all attacks now animate identically to native.

## 0.9.115-dev (2026-04-28) — Localization: Saltzpyre's dual hammers
- Renamed `Saltzpyre: Dual Hammers` → `Saltzpyre: Dual Skull-Splitters` in all 8 settings entries, matching the Skull-Splitter naming used for the single hammer and hammer+shield variants.

## 0.9.114-dev (2026-04-28) — Heavy chain windup matches release direction
- bw_sword / es_1h_sword on Bardin: H3+ chained heavy charge windup remapped to match the right-swing release direction (was vertical, now right-pose). Visual consistency through long heavy chains.

## 0.9.113-dev — H3+ chain windup added (bw_sword, es_1h_sword)
- Added `attack_swing_charge_left_pose` remap so the third-position heavy in a chain has a visible windup instead of firing native (no animation) on Bardin. Fixes "first heavy loses charge animation" reported in chained heavy sequences.

## 0.9.111-0.9.112-dev — Elf sword H3 fix
- Added `attack_swing_heavy_down_right → attack_swing_heavy_down` and `attack_swing_charge_right_diagonal_pose → attack_swing_charge_left_diagonal` to `we_1h_sword`. The elf sword has 3 distinct heavy event pairs; H3's release is now vertical to match H1.

## 0.9.108-0.9.110-dev — Cross-career H1 fixes (bw_sword, es_1h_sword, wh_1h_falchion)
- Differentiated the two heavy variants in each weapon's chain on Bardin: one variant routed to elf-H1 vertical, the other to elf-H2 right swing. Falchion got a `dr_` override so non-Bardin careers keep their existing `_default` remap unchanged.
- Added grip Z-offset `+0.05` for `bw_sword` and `es_1h_sword` on Bardin (matching the elf sword fix in 0.9.105).

## 0.9.106-0.9.107-dev — Initial bw_sword H1 redirect, scoped to Bardin
- Added `bw_sword` key remap (charge → vertical windup, release → vertical heavy) on cross-career, then scoped to `dr_` only so other careers aren't unintentionally affected.

## 0.9.105-dev — Bardin grip Z-offset
- Z-offset `+0.05` added for `we_1h_sword` (Kerillian's sword) when wielded by Bardin to fix grip riding too high. Coordinate convention discovered: weapon-local Z axis is along the blade.

## 0.9.102-0.9.104-dev — Elf sword heavy chain on Bardin
- `we_1h_sword`: H1 charge `attack_swing_charge_down → attack_swing_charge_left_diagonal`, H2 release `attack_swing_heavy_left_up → attack_swing_heavy_right`, H2 charge `attack_swing_charge_left → attack_swing_charge_right_pose`. L1 charge gains a windup as a side effect (same source event).

## 0.9.96-dev — Saltzpyre flail push-attack fix
- Narrow native-wielder redirect: on `es_1h_flail` + career prefix `wh_*`, `attack_swing_right` → `attack_swing_right_diagonal`. Vanilla `attack_swing_right` produces no visible animation on Saltzpyre's flail SM. The user explicitly authorized this native-wielder modification after `/force3p` confirmed the vanilla event was broken.

## 0.9.93-dev — Crowbill L2 fix on Kruber
- Removed `attack_swing_left → attack_swing_down` from the crowbill `_default` remap. L2 was collapsing into L1's vertical; native `attack_swing_left` plays a right swing on Kruber's crowbill SM (verified via `/force3p`).

## 0.9.92-dev — Flaming flail H1 native overhead
- Removed all template-level remaps for `one_handed_flails_flaming_template`. H1 charge `attack_swing_charge_down` and release `attack_swing_heavy_down` fire natively as the correct overhead on Bardin. Earlier versions remapped them and broke the H1 visual.

## 0.9.88-0.9.91-dev — Cross-career flail (Saltzpyre's flail) and flaming flail H2
- `es_1h_flail` on non-Saltzpyre: H1 release (`attack_swing_left`) and H2 release (`attack_swing_heavy_left`) → `attack_swing_heavy`. Direct `func()` calls in the hook (remap-table corrupts the SM for these events — same pattern as billhook `stab_02`).
- `bw_1h_flail_flaming` on non-Sienna: only H2 release (`attack_swing_heavy_left`) needs the same redirect; H1 fires natively as the correct overhead.

## 0.9.89-dev — Husk-safety for the flail redirect
- Added `_unit_career_name` helper using `Managers.player:owner(unit)`. The flail direct-redirect now gates on `is_local` AND uses the unit-owner career, so it only modifies the local player's flail when the local player is non-Saltzpyre. Husks of other players using non-flail weapons no longer have their `attack_swing_left` events hijacked.

## 0.3.0-dev (2026-04-24)

### Added: Cross-character 1H weapon unlocks for all 20 careers

Added 8 base 1H weapons that share compatible animations across all characters:
- `es_1h_sword` (Kruber's Sword) — all non-Kruber careers
- `es_1h_mace` (Kruber's Mace) — all non-Kruber careers
- `bw_sword` (Sienna's Sword) — all non-Sienna careers
- `wh_1h_falchion` (Saltzpyre's Falchion) — all non-Saltzpyre careers
- `dr_1h_axe` (Bardin's Axe) — all non-Bardin careers
- `wh_1h_axe` (Saltzpyre's Axe) — all non-Saltzpyre careers
- `we_1h_sword` (Kerillian's Sword) — all non-Kerillian careers
- `dr_1h_hammer` (Bardin's Hammer) — all non-Bardin careers

### Added: Shield weapons, spears, and career-specific unlocks

- `dr_shield_hammer` (Bardin's Hammer & Shield) — all Kruber careers
- `es_mace_shield` (Kruber's Mace & Shield) — all Bardin careers
- `es_2h_heavy_spear` (Kruber's Spear) — Foot Knight, Grail Knight
- `we_1h_spears_shield` (Kerillian's Spear & Shield) — Waystalker, Shade, Sister of the Thorn, Grail Knight
- `es_halberd` (Halberd) — Grail Knight
- `we_crossbow_repeater` (Volley Crossbow) — Waystalker, Handmaiden, Sister of the Thorn

### Changed: Settings menu restructured

VMF settings menu reorganized into Melee > Character > Career and Ranged > Character > Career hierarchy. Each weapon is an individual checkbox (all off by default).

## 0.2.1-dev (2026-04-24)

### Added: Bretonnian Sword & Shield for Mercenary

Added `es_sword_shield_breton` unlock for `es_mercenary`.

## 0.2.0-dev (2026-04-24)

### Fixed: `BackendUtils.can_wield_item` hook error on every load/toggle

**Symptom:** VMF logs `[MOD][wt][ERROR] (hook): trying to hook function or method that doesn't exist: [BackendUtils.can_wield_item]` each time the mod loads or is toggled.

**Root cause:** `BackendUtils.can_wield_item` does not exist as a hookable method at any point during the weapon_tweaker's lifecycle. The old monolithic tweaker happened to load at a time when it was available, but as a separate Workshop mod the timing is different.

**Investigation:** Tried multiple approaches — string-form hooks (`mod:hook("BackendUtils", ...)`), deferred hooks in `mod.update` with `rawget` and metatable checks — none worked because the method genuinely isn't hookable for this mod.

**Fix:** Removed the `BackendUtils.can_wield_item` hook entirely. Per the AnyWeapon mod (reference implementation), this hook is unnecessary — weapon eligibility is controlled by modifying `ItemMasterList[weapon_key].can_wield` directly (which `apply_weapon_unlocks` already does). The `ItemGridUI._on_category_index_change` hook handles inventory UI filtering.

**Rule of thumb:** Don't hook `BackendUtils.can_wield_item`. Modify `can_wield` lists on `ItemMasterList` entries directly.

### Fixed: Missing localization keys for mod settings

Added localization entries for `kruber_weapons`, `es_mercenary_weapons`, `unlock_es_mercenary_dr_1h_axe`, `debug_group`, and `enable_weapon_debug_logging`. Naming convention follows old tweaker style (e.g. "Axe (Bardin)" not "Unlock Dwarf 1H Axe").

### Added: Version logging

Mod now logs `Weapon Tweaker v<version> loaded` on init so the running version can be verified in the console log.

### Fixed: Deploy workflow

`deploy_all.ps1` now deploys directly to Workshop content folders (e.g. `552500/3712896117`) for hot reload during development, in addition to `upload/content` for Workshop uploads. The fake local install (ID `9000000002`) approach was removed — the game loads from the real Workshop folder.
