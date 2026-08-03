<!-- checker-consumed: verified-current 2026-08-02 -->
<!-- ^ Read by qa/check_decisions_wired.ps1. This doc is trusted as ground truth
     for which cross-character ports are live work. Re-verify the rows against
     wt_unlock_data.lua + the _data.lua checkboxes + the _localization.lua keys,
     then bump the date. The checker warns (advisory) once this is >30 days old. -->

# Cross-Character Port Decisions — weapon_tweaker

> **Spec change (Issue #368, 2026-07-05):** entries below that mark a weapon "CWV-managed
> (skip)" or defer it to CWV reflect the **retired** exclusion model. wt and CWV are now
> independent (overlap allowed); wt is the availability control surface. Treat those "skip"
> notes as historical — the `cwv_managed` cede is being removed and wt's toggles default ON
> for the overlapping weapons when CWV is installed. See `CROSS_MOD_ARCHITECTURE.md`.

Live document. Captures user decisions for every cross-character weapon port:
which weapon, which receiver, whether 3P render needs a target-weapon remap,
which target weapon if so. Drives `_WIELD_ANIM_CAREER_3P_PATCHES` in
`weapon_tweaker.lua` and `weapon_unlock_map` in `wt_unlock_data.lua`.

> **Conventions**
> - "Already shipped" = port + target are already in the codebase.
> - "Native fall-through" = the receiver wields without any 3P remap; engine
>   plays the source weapon's anim events directly on the receiver's body.
>   Most melee weapons take this path because the receiver's body usually
>   has compatible event vocab (or the user is OK with whatever happens).
> - "Target: <weapon>" = the receiver's body plays animations from the
>   named target weapon instead of the source weapon's native events.
>   Typically needed for ranged weapons where the receiver has no native
>   skeleton support for the source weapon's stance.

## Receiver: Kruber

### Confirmed working / shipped (12 existing ports)

| Source weapon (key) | Target (3P) | Wield event | Notes |
|---|---|---|---|
| Dwarf Greataxe (`dr_2h_axe`) | Empire 2H Hammer (`es_2h_hammer`) | (native fall-through w/ template remap) | working; heavies were sticky historically |
| Elf Greatsword (`we_2h_sword`) | Bretonnian Longsword (`es_bastard_sword`) | `to_2h_sword_we → to_bastard_sword` (`_career_anim_redirect`) + `two_handed_swords_wood_elf_template._default` | working; inventory preview regression flagged separately |
| Elf Spear (`we_spear`) | Empire Halberd (`es_halberd`) | `to_spear → to_polearm` (`_career_anim_redirect`) + `_WIELD_ANIM_CAREER_3P_PATCHES` | working |
| Elf Spear & Shield (`we_1h_spears_shield`) | Kruber's Spear & Shield (= `es_deus_01` family) | `_suffix_career_map["_1h_spear_shield"] → "_es_deus_01"` | working |
| Elf Sword (`we_1h_sword`) | Kruber 1H Sword (`es_1h_sword`) | native fall-through (`to_1h_sword`) | working |
| WH Billhook (`wh_2h_billhook`) | Empire Halberd (`es_halberd`) | `to_2h_billhook → to_polearm` + `_WIELD_ANIM_CAREER_3P_PATCHES` + new `_3p_template_remaps` entry (v0.12.102-dev fix) | wield landed but per-attack REMAP was missing on Kruber (subagent fixed) |
| WH Brace of Pistols (`wh_brace_of_pistols`) | Empire Repeater Handgun (`es_repeating_handgun`) | `to_repeating_handgun` (`_BRACE_REPEATER_BASE_WIELD_3P` patcher) + brace 3P preview/mission swap | working |
| WH Repeater Pistol (`wh_repeating_pistols`) | Empire Repeater Handgun (`es_repeating_handgun`) | `to_repeating_handgun` (`_WH_REPEATING_PISTOLS_REPEATING_HANDGUN_WIELD_3P` patcher) | working |
| Empire Flail (`es_1h_flail`) | (Kruber-native) | (native) | natively wieldable; kept in unlock_map for clarity |
| Elf Longbow (`we_longbow`) | Empire Longbow (`es_longbow`) | `to_longbow → to_es_longbow` (`_career_anim_redirect`) | working |
| Crowbill (`bw_1h_crowbill`) | Empire 1H Sword (`es_1h_sword`) | `to_1h_crowbill → to_1h_sword` (`_career_anim_redirect`) + `one_handed_crowbill._default` | regression on Kruber heavy attacks — user to retest after polearm fix v0.12.102 |
| Flaming Flail (`bw_1h_flail_flaming`) | Empire Flail (`es_1h_flail`) | **NO wield redirect yet** — `_career_anim_redirect.to_1h_flail_flaming` missing | needs fix: add wield redirect `to_1h_flail_flaming → to_1h_flail` for non-`bw_` careers |

### Removed (v0.12.102-dev cleanup)

- WH Hammer (`wh_1h_hammer`) — REMOVED from Kruber's 4 careers. Reason: analogous to Empire 1H Mace; CWV will handle hammer-vs-mace differentiation as a cosmetic variant.

### Skipped — Bardin weapons identical to Kruber natives (NEVER add to Kruber)

User confirmed 2026-05-28:

| Skipped | Identical to (Kruber native) |
|---|---|
| Dwarf 1H Hammer (`dr_1h_hammer`) | Empire 1H Mace (`es_1h_mace`) |
| Dwarf 2H Hammer (`dr_2h_hammer`) | Empire 2H Hammer (`es_2h_hammer`) |
| Dwarf Handgun (`dr_handgun`) | Empire Handgun (`es_handgun`) |
| Dwarf Hammer & Shield (`dr_shield_hammer`) | Empire Mace & Shield (`es_mace_shield`) |
| Dwarf Grudge-Raker (`dr_rakegun`) | Empire Blunderbuss (`es_blunderbuss`) |

### Bardin weapons → Kruber (Batch 1 decisions, 2026-05-28)

**Identicals — DO NOT ADD:**

| Skipped | Identical to (Kruber native) |
|---|---|
| Dwarf 1H Hammer (`dr_1h_hammer`) | Empire 1H Mace (`es_1h_mace`) |
| Dwarf 2H Hammer (`dr_2h_hammer`) | Empire 2H Hammer (`es_2h_hammer`) |
| Dwarf Handgun (`dr_handgun`) | Empire Handgun (`es_handgun`) |
| Dwarf Hammer & Shield (`dr_shield_hammer`) | Empire Mace & Shield (`es_mace_shield`) |
| Dwarf Grudge-Raker (`dr_rakegun`) | Empire Blunderbuss (`es_blunderbuss`) |
| Dwarf 1H Axe (`dr_1h_axe`) | Witch Hunter 1H Axe (`wh_1h_axe`) — Kruber gets Saltzpyre's axe, not Bardin's |
| Dwarf Crossbow (`dr_crossbow`) | Witch Hunter Crossbow (`wh_crossbow`) — Kruber's crossbow access lives in CWV |

Note: `wh_crossbow` also stripped from Bardin's 4 careers for the same reason (Bardin native `dr_crossbow` covers role). User decision 2026-05-28.

**To ADD to Kruber + animation target:**

| # | Source weapon | Target (3P) | Notes |
|---|---|---|---|
| B-cog | Dwarf Cog Hammer (`dr_2h_cog_hammer`) | Empire 2H Hammer (`es_2h_hammer` → `to_2h_hammer`) | |
| B-pick | Dwarf Pickaxe (`dr_2h_pick`) | Empire 2H Hammer (`es_2h_hammer` → `to_2h_hammer`) | |
| B-dualaxes | Dwarf Dual Axes (dr_dual_wield_axes) [SUPERSEDED] | Empire Hammer & Sword (es_dual_wield_hammer_sword -> to_dual_hammer_sword) | **SUPERSEDED - REMOVED from Kruber (#582): native Bardin Dual Axes stays Bardin-only; Kruber uses the CWV variant instead. CHANGELOG v0.12.226-dev; tombstone _wt_availability.lua; regression test issue582_native_dual_axes_cwv_ownership_boundary. Key de-backticked so the check_decisions_wired gate reads this row as inactive.** |
| B-dualhammers | Dwarf Dual Hammers (dr_dual_wield_hammers) [SUPERSEDED] | Empire Hammer & Sword (es_dual_wield_hammer_sword -> to_dual_hammer_sword) | **SUPERSEDED - REMOVED from Kruber per the Bardin batch CORRECTION below ("REMOVE from Bardin -> Kruber plan"): replaced by Saltzpyre's Dual Skullsplitters (wh_dual_hammer). See Bake status 2026-05-30 "B-dualhammers removed per correction". Key de-backticked so the gate reads this row as inactive.** |
| B-shieldaxe | Dwarf Axe & Shield (`dr_shield_axe`) | (default: native fall-through; if broken: `es_mace_shield` → `to_1h_mace_shield`) | Probably works natively; **CWV holds the answer** — they made a Saltzpyre axe + Kruber shield combo for Kruber that works perfectly; mirror that approach if redirect needed |
| B-throw | Dwarf Throwing Axes (`dr_1h_throwing_axes`) | Empire 1H Mace (`es_1h_mace` → `to_1h_mace`) | |
| B-drakepistol | Dwarf Drakefire Pistols (`dr_drake_pistol`) | Empire Repeater Handgun (`es_repeating_handgun` → `to_repeating_handgun`) | **HIDE offhand pistol** — Kruber holds only the right-hand unit |
| B-drakegun | Dwarf Drakegun (`dr_drakegun`) | Empire Blunderbuss (`es_blunderbuss` → `to_blunderbuss`) | |
| B-steampistol | Dwarf Masterwork Pistol (`dr_steam_pistol`) | Empire Repeater Handgun (`es_repeating_handgun` → `to_repeating_handgun`) | |
| B-deus | Dwarf Trollhammer Torpedo (`dr_deus_01`) | Empire Blunderbuss (`es_blunderbuss` → `to_blunderbuss`) | Confirmed via existing loc key `"Bardin: Trollhammer Torpedo"` |
| **BONUS** | Witch Hunter 1H Axe (`wh_1h_axe`) | (decided previously, fully functional) | User confirmed Kruber gets Saltzpyre's axe; add to all 4 Kruber careers |

Implementation note: Wave 1 = add to `weapon_unlock_map` + checkboxes + loc keys. Wave 2 = add wield redirects to `_career_anim_redirect` AND/OR `_WIELD_ANIM_CAREER_3P_PATCHES`. Wave 3 = drakefire offhand-hide implementation (likely a new entry in the `MenuWorldPreviewer._spawn_item_unit` + `GearUtils.create_equipment` swap dispatch).

### Kerillian weapons → Kruber (Batch 2 decisions, 2026-05-28)

**Loc dumps (per the weapon-id documentation rule):**
- `we_1h_axe` = Kerillian: 1H Axe (Elven)
- `we_2h_axe` = Kerillian: 2H Axe (Glaive / Greataxe)
- `we_dual_wield_daggers` = Kerillian: Dual Daggers
- `we_dual_wield_swords` = Kerillian: Dual Swords
- `we_dual_wield_sword_dagger` = Kerillian: Sword & Dagger
- `we_deus_01` = **Kerillian: Moonfire Bow** (Carousel DLC ranged bow)
- `we_shortbow` = Kerillian: Shortbow
- `we_shortbow_hagbane` = Kerillian: Hagbane Shortbow (poison)
- `we_javelin` = Kerillian: Javelin (thrown)
- `we_life_staff` = **Kerillian: Deepwood Staff** (Sister of the Thorn career-locked staff)
- `we_crossbow_repeater` = Kerillian: Repeater Crossbow

**To ADD:**

| Source weapon | Target (3P) | Notes |
|---|---|---|
| `we_1h_axe` (Elven 1H Axe) | Witch Hunter 1H Axe (`wh_1h_axe`) | Routes via `wh_1h_axe`, which itself works natively on Kruber via `_career_anim_redirect.to_1h_axe → to_1h_sword` |
| `we_2h_axe` (Glaive) | Empire 2H Hammer (`es_2h_hammer` → `to_2h_hammer`) | |
| `we_dual_wield_daggers` (Dual Daggers) | Empire Hammer & Sword (`es_dual_wield_hammer_sword` → `to_dual_hammer_sword`) | |
| `we_dual_wield_swords` (Dual Swords) | Empire Hammer & Sword (`es_dual_wield_hammer_sword` → `to_dual_hammer_sword`) | |
| `we_dual_wield_sword_dagger` (Sword & Dagger) | Empire Hammer & Sword (`es_dual_wield_hammer_sword` → `to_dual_hammer_sword`) | |
| `we_deus_01` (Moonfire Bow) | Empire Longbow (`es_longbow` → `to_es_longbow`) | |
| `we_shortbow` (Shortbow) | Empire Longbow (`es_longbow` → `to_es_longbow`) | |
| `we_shortbow_hagbane` (Hagbane Shortbow) | Empire Longbow (`es_longbow` → `to_es_longbow`) | |
| `we_javelin` (Javelin) | **EXPERIMENTAL** — try Kruber's Spear & Shield (`es_deus_01` family) first; revisit after in-game test | User flagged this needs experimentation |
| `we_crossbow_repeater` (Repeater Crossbow) | Empire Repeater Handgun (`es_repeating_handgun` → `to_repeating_handgun`) | |

**Pending decision:**
- `we_life_staff` (Deepwood Staff) — user not yet decided. Need to know whether to add at all (Sister-of-the-Thorn-only weapon, magic ranged) and if yes, what target.

### Bardin batch CORRECTION (2026-05-28)

**REMOVE from Bardin → Kruber plan:**
- `dr_dual_wield_hammers` (Bardin: Dual Hammers) — replaced by Saltzpyre's `wh_dual_hammer` (more sensible source for the role)

### Saltzpyre weapons → Kruber (Batch 3 decisions, 2026-05-28)

**Loc dumps:**
- `wh_1h_axe` = Saltzpyre: 1H Axe (already decided in Bardin batch as the replacement for `dr_1h_axe`)
- `wh_dual_hammer` = Saltzpyre: Dual Hammers
- `wh_dual_wield_axe_falchion` = Saltzpyre: Axe & Falchion (CWV-managed, skip)
- `wh_2h_sword` = Saltzpyre: Two-Handed Sword
- `wh_2h_hammer` = Saltzpyre: Two-Handed Hammer
- `wh_fencing_sword` = Saltzpyre: Rapier
- `wh_crossbow_repeater` = Saltzpyre: Volley Crossbow
- `wh_deus_01` = **Saltzpyre: Griffon-foot** (Carousel DLC four-barrel pistol)

**Identicals — DO NOT ADD:**

| Skipped | Identical to (Kruber native) |
|---|---|
| Saltzpyre: Two-Handed Sword (`wh_2h_sword`) | Empire: 2H Sword (`es_2h_sword`) |

**To ADD to Kruber:**

| Source weapon (key) | Display name | Target (3P) | Notes |
|---|---|---|---|
| `wh_1h_axe` | Saltzpyre: 1H Axe | (native fall-through via `_career_anim_redirect.to_1h_axe → to_1h_sword`) | Already decided as replacement for `dr_1h_axe`. Confirmed fully functional. |
| `wh_dual_hammer` | Saltzpyre: Dual Hammers | Empire: Hammer & Sword (`es_dual_wield_hammer_sword` → `to_dual_hammer_sword`) | Internal field name `dual_hammer_sword` is misleading — the in-game weapon is actually a mace + sword. Document at the redirect site. |
| `wh_2h_hammer` | Saltzpyre: Two-Handed Hammer | Empire: 2H Hammer (`es_2h_hammer` → `to_2h_hammer`) | NOT identical to Kruber's; user confirmed visually distinct |
| `wh_fencing_sword` | Saltzpyre: Rapier | **Empire: Sword & Shield (`es_sword_shield` → `to_1h_sword_shield`)** | Kruber doesn't author offhand-pistol animation that Saltzpyre's rapier expects; user will experiment with sword+shield thrusts + pistol in shield hand. Special-action pistol fire may map to shield-bash anim — user to iterate in-game |
| `wh_crossbow_repeater` | Saltzpyre: Volley Crossbow | Empire: Repeater Handgun (`es_repeating_handgun` → `to_repeating_handgun`) | NOT analogous to Elf Repeater Crossbow; BOTH enabled on Kruber |
| `wh_deus_01` | Saltzpyre: Griffon-foot | Empire: Repeater Handgun (`es_repeating_handgun` → `to_repeating_handgun`) with **repeater handgun 3P MODEL swap + likely offhand hide**. Implementation pattern: **mirror Brace of Pistols on Kruber** — preview swap + in-mission swap + force-load of repeater handgun mesh package. |

### Per-hand independent grip tuning (hold-pose tuner enhancement)

**Requirement raised 2026-05-28:** user needs to tweak the offhand and main hand separately for grip offsets and rotation. Current `wt_dev_hold_pose` has a single slider set + hand dropdown — switching hands loses the previous hand's values.

**Implementation plan:** add per-hand state persistence so each hand has its own offset/rotation memory; the `/wt_dump_hold_pose` command emits both sets. Filed as task #24. Implementation deferred until current port-walk decisions are baked.

### Warrior Priest weapons → Kruber (Batch 4 decisions, 2026-05-28)

**Loc dumps:**
- `wh_flail_shield` = Saltzpyre: Flail and Shield (WP-only in vanilla)
- `wh_hammer_book` = Saltzpyre: Hammer and Tome (WP-only in vanilla)
- `wh_hammer_shield` = Saltzpyre: Skull-Splitter and Shield (WP-only in vanilla)

**Identicals — DO NOT ADD:**

| Skipped | Identical to (Kruber native) |
|---|---|
| Saltzpyre: Skull-Splitter and Shield (`wh_hammer_shield`) | Empire: Mace & Shield (`es_mace_shield`) |

**To ADD to Kruber:**

| Source weapon (key) | Display name | Target (3P) |
|---|---|---|
| `wh_flail_shield` | Saltzpyre: Flail and Shield | Empire: Mace & Shield (`es_mace_shield` → `to_1h_mace_shield`) |
| `wh_hammer_book` | Saltzpyre: Hammer and Tome | Empire: Mace & Shield (`es_mace_shield` → `to_1h_mace_shield`) |

### Sienna weapons → Kruber (Batch 5 decisions, 2026-05-28)

**Loc dumps:**
- `bw_1h_mace` = Sienna: Mace
- `bw_dagger` = Sienna: Dagger
- `bw_flame_sword` = Sienna: Flame Sword
- `bw_ghost_scythe` = Sienna: Ensorcelled Reaper (scythe)
- `bw_sword` = Sienna: Sword
- `bw_skullstaff_beam` = Sienna: Beam Staff
- `bw_skullstaff_fireball` = Sienna: Fireball Staff
- `bw_skullstaff_flamethrower` = Sienna: Flamestorm Staff
- `bw_skullstaff_geiser` = Sienna: Conflagration Staff
- `bw_skullstaff_spear` = Sienna: Bolt Staff
- `bw_necromancy_staff` = Sienna: Soulstealer Staff (Necromancer career-locked)
- `bw_deus_01` = Sienna: Coruscation Staff (Carousel DLC deus tier)

Already on Kruber from earlier:
- `bw_1h_crowbill` = Sienna: Crowbill → maps to Kruber's 1H Sword
- `bw_1h_flail_flaming` = Sienna: Flaming Flail → maps to Kruber's Flail

**Identicals — DO NOT ADD:**

| Skipped | Identical to (Kruber native) |
|---|---|
| Sienna: Sword (`bw_sword`) | Empire: 1H Sword (`es_1h_sword`) |

**To ADD to Kruber:**

| Source weapon (key) | Display name | Target (3P) | Notes |
|---|---|---|---|
| `bw_1h_mace` | Sienna: Mace | Empire: 2H Hammer (`es_2h_hammer` → `to_2h_hammer`) | User explicitly chose Greathammer (despite mace being 1H); held two-handed by Kruber |
| `bw_dagger` | Sienna: Dagger | Empire: 1H Sword (`es_1h_sword` → `to_1h_sword`) | |
| `bw_flame_sword` | Sienna: Flame Sword | Empire: 1H Sword (`es_1h_sword` → `to_1h_sword`) | |
| `bw_ghost_scythe` | Sienna: Ensorcelled Reaper | Empire: 2H Hammer (`es_2h_hammer` → `to_2h_hammer`) | |
| `bw_skullstaff_beam` | Sienna: Beam Staff | Empire: 2H Hammer (`es_2h_hammer` → `to_2h_hammer`) | Magic ranged → Kruber holds as 2H melee. User will pick per-attack: melee anim for some actions, no anim (UNSET) for others |
| `bw_skullstaff_fireball` | Sienna: Fireball Staff | Empire: 2H Hammer (`es_2h_hammer` → `to_2h_hammer`) | same |
| `bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | Empire: 2H Hammer (`es_2h_hammer` → `to_2h_hammer`) | same |
| `bw_skullstaff_geiser` | Sienna: Conflagration Staff | Empire: 2H Hammer (`es_2h_hammer` → `to_2h_hammer`) | same |
| `bw_skullstaff_spear` | Sienna: Bolt Staff | Empire: 2H Hammer (`es_2h_hammer` → `to_2h_hammer`) | same |
| `bw_necromancy_staff` | Sienna: Soulstealer Staff | Empire: 2H Hammer (`es_2h_hammer` → `to_2h_hammer`) | Necromancer-only in vanilla; on Kruber as cross-character |
| `bw_deus_01` | Sienna: Coruscation Staff | Empire: 2H Hammer (`es_2h_hammer` → `to_2h_hammer`) | Carousel DLC deus tier |

### Kruber receiver — STATUS

Inventory availability is fully wired for the rows recorded below. Animation
target and presentation verification remain separate concerns tracked by the
animation coverage and issue records.

**Shipped — inventory-wiring reconciliation (2026-08-02):**

The checker verifies each row below is present for all four Kruber careers in
`weapon_unlock_map`, has its availability checkbox, and has its localization
key. These rows reconcile later shipped state that the earlier walkthrough did
not record; they do not make new animation-target decisions.

| Source weapon (key) | Display name | Reconciliation evidence |
|---|---|---|
| `we_life_staff` | Kerillian: Deepwood Staff | Fully wired on all Kruber careers; supersedes the stale pending note above. |
| `wh_1h_falchion` | Saltzpyre: Falchion | Fully wired on all Kruber careers. |
| `wh_crossbow` | Saltzpyre: Crossbow | Fully wired on all Kruber careers. |

### Kruber → Kerillian (Batch 1 decisions, 2026-05-28)

**Loc dumps (Kruber natives candidate for Kerillian):**
- `es_1h_flail` = Empire: Flail
- `es_1h_sword` = Empire: 1H Sword
- `es_2h_hammer` = Empire: Greathammer
- `es_2h_heavy_spear` = Empire: Tuskgor Spear
- `es_2h_sword_executioner` = Empire: Executioner Sword
- `es_bastard_sword` = Empire: Bretonnian Longsword
- `es_blunderbuss` = Empire: Blunderbuss
- `es_dual_wield_hammer_sword` = Empire: Mace & Sword (internal name misleading — actually mace + sword)
- `es_halberd` = Empire: Halberd
- `es_handgun` = Empire: Handgun
- `es_mace_shield` = Empire: Mace & Shield
- `es_repeating_handgun` = Empire: Repeater Handgun
- `es_sword_shield` = Empire: Sword & Shield
- `es_sword_shield_breton` = Empire: Bretonnian Sword & Shield

**Identicals — DO NOT ADD:**

| Skipped | Reason |
|---|---|
| Empire: 1H Sword (`es_1h_sword`) | Sienna's `bw_sword` is the closest existing match in Kerillian's options; Empire's and Sienna's are analogous so no need for the Empire variant |

**To ADD to Kerillian:**

| Source weapon (key) | Display name | Target (3P) |
|---|---|---|
| `es_1h_flail` | Empire: Flail | Kerillian: 1H Sword (`we_1h_sword` → `to_1h_sword`) |
| `es_2h_hammer` | Empire: Greathammer | Kerillian: Glaive / 2H Axe (`we_2h_axe` → `to_2h_axe`) |
| `es_2h_heavy_spear` | Empire: Tuskgor Spear | Kerillian: Spear (`we_spear` → `to_spear`) |
| `es_2h_sword_executioner` | Empire: Executioner Sword | Kerillian: 2H Sword (`we_2h_sword` → `to_2h_sword_we`) |
| `es_bastard_sword` | Empire: Bretonnian Longsword | Kerillian: 2H Sword (`we_2h_sword` → `to_2h_sword_we`) |
| `es_blunderbuss` | Empire: Blunderbuss | Kerillian: Volley Crossbow (`we_crossbow_repeater` → `to_repeating_crossbow_elf`) |
| `es_dual_wield_hammer_sword` | Empire: Mace & Sword | Kerillian: Sword & Dagger (`we_dual_wield_sword_dagger` → `to_dual_wield_sword_dagger`) |
| `es_halberd` | Empire: Halberd | Kerillian: Spear (`we_spear` → `to_spear`) |
| `es_handgun` | Empire: Handgun | Kerillian: Volley Crossbow (`we_crossbow_repeater`) |
| `es_mace_shield` | Empire: Mace & Shield | Kerillian: Spear & Shield (`we_1h_spears_shield` → `to_1h_spear_shield`) |
| `es_repeating_handgun` | Empire: Repeater Handgun | Kerillian: Volley Crossbow (`we_crossbow_repeater`) |
| `es_sword_shield` | Empire: Sword & Shield | Kerillian: Spear & Shield (`we_1h_spears_shield`). Reference CWV's existing sword+shield-on-Kerillian implementation for grip/scale precedent |
| `es_sword_shield_breton` | Empire: Bretonnian Sword & Shield | Kerillian: Spear & Shield (`we_1h_spears_shield`) |

### Bardin → Kerillian (Batch 2 decisions, 2026-05-28)

**Loc dumps:** see prior section + below
- `wh_1h_axe` = Saltzpyre: 1H Axe (BONUS — user routes Kerillian's 1h-axe need through Saltzpyre, not Bardin)

**Identicals / superseded — DO NOT ADD:**

| Skipped | Reason |
|---|---|
| Bardin: 1H Axe (`dr_1h_axe`) | Saltzpyre's `wh_1h_axe` is the preferred route → maps to Kerillian's `we_1h_axe`. No need for Bardin's variant. |
| Bardin: 2H Hammer (`dr_2h_hammer`) | Kruber's Greathammer (`es_2h_hammer`, decided EK3) is the preferred 2H-hammer route. Bardin's variant superseded. |
| Bardin: Handgun (`dr_handgun`) | Kruber's `es_handgun` (decided EK10 → volley crossbow) is the preferred handgun route. |
| Bardin: Hammer & Shield (`dr_shield_hammer`) | Same as Kruber's Mace & Shield (decided EK11 → spear & shield). No need for Bardin's variant. |

**To ADD to Kerillian:**

| Source weapon (key) | Display name | Target (3P) | Notes |
|---|---|---|---|
| `wh_1h_axe` | Saltzpyre: 1H Axe | Kerillian: 1H Elf Axe (`we_1h_axe` → `to_1h_axe`) | NEW PORT for Kerillian — user explicitly added |
| `dr_1h_hammer` | Bardin: 1H Hammer | Kerillian: 1H Elf Axe (`we_1h_axe` → `to_1h_axe`) | |
| `dr_1h_throwing_axes` | Bardin: Throwing Axes | Kerillian: Javelin (`we_javelin` → `to_javelin`) | |
| `dr_2h_axe` | Bardin: Greataxe | Kerillian: Glaive (`we_2h_axe` → `to_2h_axe`) | |
| `dr_2h_cog_hammer` | Bardin: Cog Hammer | Kerillian: Glaive (`we_2h_axe` → `to_2h_axe`) | |
| `dr_2h_pick` | Bardin: Pickaxe | Kerillian: Glaive (`we_2h_axe` → `to_2h_axe`) | |
| `dr_crossbow` | Bardin: Crossbow | Kerillian: Repeater Crossbow (`we_crossbow_repeater` → `to_repeating_crossbow_elf`) | |
| `dr_deus_01` | Bardin: Trollhammer Torpedo | Kerillian: Repeater Crossbow (`we_crossbow_repeater`) | |
| `dr_drake_pistol` | Bardin: Drakefire Pistols | Kerillian: Repeater Crossbow (`we_crossbow_repeater`) + **HIDE offhand pistol** | Same offhand-hide pattern as Drakefire on Kruber |
| `dr_drakegun` | Bardin: Drakegun | Kerillian: Repeater Crossbow (`we_crossbow_repeater`) | |
| `dr_dual_wield_axes` | Bardin: Dual Axes | Kerillian: Dual Swords (`we_dual_wield_swords` → `to_dual_wield_swords`) | |
| `dr_dual_wield_hammers` | Bardin: Dual Hammers | Kerillian: Dual Swords (`we_dual_wield_swords`) | |
| `dr_rakegun` | Bardin: Grudge-Raker | Kerillian: Repeater Crossbow (`we_crossbow_repeater`) | |
| `dr_shield_axe` | Bardin: Axe & Shield | Kerillian: Spear & Shield (`we_1h_spears_shield` → `to_1h_spear_shield`) | |
| `dr_steam_pistol` | Bardin: Masterwork Pistol | Kerillian: Repeater Crossbow (`we_crossbow_repeater`) | |

### Saltzpyre → Kerillian (Batch 3 decisions, 2026-05-30) — SK1-SK15

**Loc dumps:**
- `wh_1h_falchion` = Saltzpyre: Falchion
- `wh_1h_hammer` = Saltzpyre: 1H Hammer
- `wh_2h_billhook` = Saltzpyre: Billhook
- `wh_2h_hammer` = Saltzpyre: 2H Hammer
- `wh_2h_sword` = Saltzpyre: 2H Sword (**NOT identical to Elf 2H Sword** per user 2026-05-30 — distinction: WH receiver Kruber skips because analogous to `es_2h_sword`, but Kerillian receiver gets it because distinct from `we_2h_sword`)
- `wh_brace_of_pistols` = Saltzpyre: Brace of Pistols
- `wh_crossbow` = Saltzpyre: Crossbow
- `wh_deus_01` = Saltzpyre: Griffon-foot (Carousel DLC 4-barrel pistol)
- `wh_dual_hammer` = Saltzpyre: Dual Hammers
- `wh_dual_wield_axe_falchion` = Saltzpyre: Axe & Falchion
- `wh_fencing_sword` = Saltzpyre: Rapier
- `wh_repeating_pistols` = Saltzpyre: Repeater Pistol
- `wh_flail_shield` = WP: Flail and Shield
- `wh_hammer_book` = WP: Hammer and Tome
- `wh_hammer_shield` = WP: Skull-Splitter and Shield

**To ADD to Kerillian (all 15 — no skips):**

| Source weapon (key) | Display name | Target (3P) | Notes |
|---|---|---|---|
| `wh_1h_falchion` | Saltzpyre: Falchion | Kerillian: 1H Sword (`we_1h_sword` → `to_1h_sword`) | |
| `wh_1h_hammer` | Saltzpyre: 1H Hammer | Kerillian: 1H Elf Axe (`we_1h_axe` → `to_1h_axe`) | |
| `wh_2h_billhook` | Saltzpyre: Billhook | Kerillian: Spear (`we_spear` → `to_spear`) | |
| `wh_2h_hammer` | Saltzpyre: 2H Hammer | Kerillian: Glaive (`we_2h_axe` → `to_2h_axe`) | |
| `wh_2h_sword` | Saltzpyre: 2H Sword | Kerillian: Elf 2H Sword (`we_2h_sword` → `to_2h_sword_we`) | **NOT identical to Elf 2H Sword** — user distinguishes |
| `wh_brace_of_pistols` | Saltzpyre: Brace of Pistols | **MODEL: `wh_repeating_pistols` (Saltzpyre Repeater Pistol)**; **ANIMATIONS: `we_crossbow_repeater` → `to_repeating_crossbow_elf`** | Special 2-target port: 3P model swap to Repeater Pistol unit + animations from Elf Repeater Crossbow. Wave 3 needs new swap-dispatch entry mirroring Brace-on-Kruber pattern but with `wh_repeating_pistols` mesh as target. |
| `wh_crossbow` | Saltzpyre: Crossbow | Kerillian: Repeater Crossbow (`we_crossbow_repeater` → `to_repeating_crossbow_elf`) | |
| `wh_deus_01` | Saltzpyre: Griffon-foot | **MODEL: `wh_repeating_pistols` (Saltzpyre Repeater Pistol)**; **ANIMATIONS: `we_crossbow_repeater` → `to_repeating_crossbow_elf`** | Same special 2-target pattern as `wh_brace_of_pistols`. May also need offhand hide. |
| `wh_dual_hammer` | Saltzpyre: Dual Hammers | Kerillian: Dual Swords (`we_dual_wield_swords` → `to_dual_wield_swords`) | |
| `wh_dual_wield_axe_falchion` | Saltzpyre: Axe & Falchion | Kerillian: Sword & Dagger (`we_dual_wield_sword_dagger` → `to_dual_wield_sword_dagger`) | |
| `wh_fencing_sword` | Saltzpyre: Rapier | Kerillian: 1H Sword (`we_1h_sword` → `to_1h_sword`) | |
| `wh_repeating_pistols` | Saltzpyre: Repeater Pistol | Kerillian: Repeater Crossbow (`we_crossbow_repeater` → `to_repeating_crossbow_elf`) | |
| `wh_flail_shield` | WP: Flail and Shield | Kerillian: Spear & Shield (`we_1h_spears_shield` → `to_1h_spear_shield`) | |
| `wh_hammer_book` | WP: Hammer and Tome | Kerillian: Spear & Shield (`we_1h_spears_shield` → `to_1h_spear_shield`) | |
| `wh_hammer_shield` | WP: Skull-Splitter and Shield | Kerillian: Spear & Shield (`we_1h_spears_shield` → `to_1h_spear_shield`) | |

### UI restructure (Batch 3 follow-up, 2026-05-30)

User wants the weapon-availability widget tree restructured: characters at top level, melee/ranged nested under each character (instead of melee/ranged at top with characters nested inside). Subagent to handle. Affects `weapon_tweaker_data.lua` widget tree and may need new loc keys for the per-character containers.

### Sienna → Kerillian (Batch 4 decisions, 2026-05-31) — SiK1-SiK14

**Loc dumps:** see prior section + below
- `bw_1h_crowbill` = Sienna: Crowbill
- `bw_1h_flail_flaming` = Sienna: Flaming Flail
- `bw_1h_mace` = Sienna: Mace
- `bw_dagger` = Sienna: Dagger
- `bw_flame_sword` = Sienna: Flame Sword
- `bw_ghost_scythe` = Sienna: Ensorcelled Reaper
- `bw_sword` = Sienna: Sword
- `bw_skullstaff_beam` = Sienna: Beam Staff
- `bw_skullstaff_fireball` = Sienna: Fireball Staff
- `bw_skullstaff_flamethrower` = Sienna: Flamestorm Staff
- `bw_skullstaff_geiser` = Sienna: Conflagration Staff
- `bw_skullstaff_spear` = Sienna: Bolt Staff
- `bw_necromancy_staff` = Sienna: Soulstealer Staff
- `bw_deus_01` = Sienna: Coruscation Staff

**Identicals — DO NOT ADD:**

| Skipped | Reason |
|---|---|
| Sienna: Mace (`bw_1h_mace`) | Kerillian already has `es_1h_mace` (Empire mace) in her unlock_map |
| Sienna: Sword (`bw_sword`) | Identical to Kerillian's `we_1h_sword` (Elf 1H Sword) |

**To ADD to Kerillian:**

| Source weapon (key) | Display name | Target (3P) |
|---|---|---|
| `bw_1h_crowbill` | Sienna: Crowbill | Kerillian: 1H Sword (`we_1h_sword` → `to_1h_sword`) |
| `bw_1h_flail_flaming` | Sienna: Flaming Flail | Kerillian: 1H Sword (`we_1h_sword` → `to_1h_sword`) |
| `bw_dagger` | Sienna: Dagger | Kerillian: 1H Sword (`we_1h_sword` → `to_1h_sword`) |
| `bw_flame_sword` | Sienna: Flame Sword | Kerillian: 1H Sword (`we_1h_sword` → `to_1h_sword`) |
| `bw_ghost_scythe` | Sienna: Ensorcelled Reaper | Kerillian: Glaive (`we_2h_axe` → `to_2h_axe`) |
| `bw_skullstaff_beam` | Sienna: Beam Staff | Kerillian: Glaive (`we_2h_axe` → `to_2h_axe`) |
| `bw_skullstaff_fireball` | Sienna: Fireball Staff | Kerillian: Glaive (`we_2h_axe` → `to_2h_axe`) |
| `bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | Kerillian: Glaive (`we_2h_axe` → `to_2h_axe`) |
| `bw_skullstaff_geiser` | Sienna: Conflagration Staff | Kerillian: Glaive (`we_2h_axe` → `to_2h_axe`) |
| `bw_skullstaff_spear` | Sienna: Bolt Staff | Kerillian: Glaive (`we_2h_axe` → `to_2h_axe`) |
| `bw_necromancy_staff` | Sienna: Soulstealer Staff | Kerillian: Glaive (`we_2h_axe` → `to_2h_axe`) |
| `bw_deus_01` | Sienna: Coruscation Staff | Kerillian: Glaive (`we_2h_axe` → `to_2h_axe`) |

## Receiver: Saltzpyre (non-WP)

Saltzpyre non-WP receiver careers: `wh_captain`, `wh_bountyhunter`, `wh_zealot`.
(Warrior Priest handled separately — see `feedback_vt2_no_bows_on_warrior_priest.md`
and the WP receiver section below.)

### Kruber weapons → Saltzpyre (Batch K→S decisions, 2026-05-31) — KS1-KS12

**Loc dumps:** see "Kruber → Kerillian (Batch 1)" — same Empire weapon set.

**Identicals / superseded — DO NOT ADD:**

| # | Skipped | Reason |
|---|---|---|
| KS2 | `es_2h_sword` (Empire: 2H Sword) | Analogous to Saltzpyre native `wh_2h_sword`. |

> **SUPERSEDED 2026-06-04**: the four historical target-unclear rows below
> were replaced by the shipped Shield-Combos Override later in this receiver
> section. They remain only as decision history.

**SUPERSEDED — prior target-unclear rows, DO NOT ADD from this historical table:**

| # | Source weapon | Display name | Default suggestion | Why flagged |
|---|---|---|---|---|
| KS6 | `es_mace_shield` | Empire: Mace & Shield | (none) | Saltzpyre non-WP careers don't natively author shield-stance animations. WP careers do (`wh_flail_shield`, `wh_hammer_shield`, `wh_hammer_book`) but they're explicitly excluded from this batch. No clean target for non-WP — needs user creative decision. |
| KS7 | `es_sword_shield` | Empire: Sword & Shield | (none) | Same as KS6. |
| KS8 | `es_sword_shield_breton` | Empire: Bretonnian Sword & Shield | (none) | Same as KS6. |
| KS9 | `es_deus_01` | Empire: Spear and Shield (Kruber's CW deus) | (none) | Same as KS6 — spear+shield combo lacks Saltzpyre non-WP target. |

**To ADD to Saltzpyre non-WP (7 weapons × 3 careers = 21 entries):**

| # | Source weapon (key) | Display name | Target (3P) | Class |
|---|---|---|---|---|
| KS1 | `es_bastard_sword` | Kruber: Bretonnian Longsword | Saltzpyre 2H Sword (`wh_2h_sword` → `to_2h_sword`) | melee |
| KS3 | `es_2h_sword_executioner` | Kruber: Executioner Sword | Saltzpyre 2H Sword (`wh_2h_sword` → `to_2h_sword`) | melee |
| KS4 | `es_2h_hammer` | Kruber: Greathammer | Saltzpyre 2H Hammer (`wh_2h_hammer` → `to_2h_hammer`) | melee |
| KS5 | `es_dual_wield_hammer_sword` | Kruber: Mace and Sword | Saltzpyre Dual Hammers (`wh_dual_hammer` → `to_dual_hammer`) | melee |
| KS10 | `es_blunderbuss` | Kruber: Blunderbuss | Saltzpyre Crossbow (`wh_crossbow` → `to_crossbow`) — closest spread-fire role | ranged |
| KS11 | `es_handgun` | Kruber: Handgun | Saltzpyre Crossbow (`wh_crossbow` → `to_crossbow`) | ranged |
| KS12 | `es_repeating_handgun` | Kruber: Repeater Handgun | Saltzpyre Repeater Pistol (`wh_repeating_pistols` → `to_repeating_handgun`-family) | ranged |

Implementation note: KS10-KS12 ranged ports need Wave 2 anim redirects on the
Saltzpyre side (Saltzpyre has crossbow + repeater pistol vocab but no native
handgun/blunderbuss/repeater-handgun events). KS1/KS3/KS4/KS5 melee ports use
native Saltzpyre 2H-sword / 2H-hammer / dual-hammer event vocab; should fall
through cleanly without explicit redirects.

### Bardin weapons → Saltzpyre non-WP (Batch A, 2026-05-31)

> **SUPERSEDED 2026-06-04**: The 4 shield-combo SKIP rows below
> (BS-A-skip-1 `es_mace_shield`, BS-A-skip-2 `es_sword_shield`,
> BS-A-skip-3 `es_sword_shield_breton`, BS-A-skip-4 `es_deus_01`) are
> superseded by the "Batch E + Shield-Combos Override (2026-06-04)" section
> below. User reversed the "non-WP has no shield stance" reasoning: all 4
> Empire shield combos (plus the previously-unqueued Bardin and Kerillian
> shield combos) are now ADDED to Saltzpyre non-WP with target
> `wh_dual_wield_axe_falchion`. Original skip text retained for history.

**Batch A SKIP decisions:**

| # | Skipped | Reason |
|---|---|---|
| BS-A-skip-1 | `es_mace_shield` (Empire: Mace & Shield) | Identical to Saltzpyre native `wh_hammer_shield` (Saltzpyre Skull-Splitter and Shield). User decision 2026-05-31. |
| BS-A-skip-2 | `es_sword_shield` (Empire: Sword & Shield) | Deferred to WP receiver consideration. Saltzpyre non-WP careers (`wh_captain`, `wh_bountyhunter`, `wh_zealot`) have no native shield stance; user explicitly said treat WP as separate character. |
| BS-A-skip-3 | `es_sword_shield_breton` (Empire: Bretonnian Sword & Shield) | Same as BS-A-skip-2 — deferred to WP receiver consideration. |
| BS-A-skip-4 | `es_deus_01` (Empire: Spear and Shield, Kruber's CW deus) | Same as BS-A-skip-2 — deferred to WP receiver consideration. |

**Batch A ADD decisions (6 weapons × 3 careers = 18 entries):**

| # | Source weapon (key) | Display name | Target (3P) | Class |
|---|---|---|---|---|
| BS-A1 | dr_1h_axe [SUPERSEDED] | Bardin: 1H Axe | REMOVED from non-WP Saltzpyre - redundant with native Saltzpyre 1H Axe (wh_1h_axe). #187; CHANGELOG v0.12.173-dev; regression test no_redundant_bardin_1h_on_saltzpyre. Key de-backticked so the gate reads this row as inactive. | melee |
| BS-A2 | dr_1h_hammer [SUPERSEDED] | Bardin: 1H Hammer | REMOVED from non-WP Saltzpyre - redundant with native Saltzpyre Skullsplitter (wh_1h_hammer). #187; CHANGELOG v0.12.173-dev; regression test no_redundant_bardin_1h_on_saltzpyre. Key de-backticked so the gate reads this row as inactive. | melee |
| BS-A3 | `dr_2h_axe` | Bardin: Greataxe | Saltzpyre 2H Sword (`wh_2h_sword`) | melee |
| BS-A4 | `dr_2h_cog_hammer` | Bardin: Cog Hammer | Saltzpyre 2H Hammer (`wh_2h_hammer`) | melee |
| BS-A5 | `dr_2h_hammer` | Bardin: 2H Hammer | Saltzpyre 2H Hammer (`wh_2h_hammer`) | melee |
| BS-A6 | `dr_2h_pick` | Bardin: Pickaxe | Saltzpyre 2H Hammer (`wh_2h_hammer`) | melee |

### Bardin weapons → Saltzpyre non-WP (Batch B, 2026-05-31)

Continuation of Batch A — remaining DR source weapons not yet routed to
non-WP Saltzpyre. Routes 2 melee dual-wield weapons + 6 ranged weapons.

**Batch B SKIP decisions:**

| # | Skipped | Reason |
|---|---|---|
| BS-B-skip-1 | `dr_crossbow` (Bardin: Crossbow) | Identical to Saltzpyre native `wh_crossbow`; Saltzpyre already has Crossbow access. No additional value. |
| BS-B-skip-2 | `dr_handgun` (Bardin: Handgun) | Identical to Kruber's `es_handgun` (Empire Handgun); Kruber's is the preferred route and is already added to non-WP careers in Batch KS (KS11). Adding the Bardin variant would duplicate the functional port through a less-canonical source. |

**Batch B ADD decisions (8 weapons × 3 careers = 24 entries):**

| # | Source weapon (key) | Display name | Target (3P) | Class | User note |
|---|---|---|---|---|---|
| BS-B1 | `dr_1h_throwing_axes` | Bardin: Throwing Axes | Saltzpyre 1H Axe (`wh_1h_axe`) | ranged | "will likely be goofy but not much other choice" — Saltzpyre has no native thrown-weapon 3P vocab; falling back on 1H axe melee animations for the wind-up. |
| BS-B2 | dr_dual_wield_axes [SUPERSEDED] | Bardin: Dual Axes | ~~Saltzpyre Dual Skull-Splitters~~ (removed) | melee | **SUPERSEDED - REMOVED from non-WP Saltzpyre (#582): native Bardin Dual Axes stays Bardin-only; Saltzpyre uses the CWV variant instead. CHANGELOG v0.12.226-dev; tombstone _wt_availability.lua; regression test issue582_native_dual_axes_cwv_ownership_boundary. Key de-backticked so the gate reads this row as inactive.** Original note (history): Per user: WP dual hammer animations are shared with non-WP Saltzpyre because they use the same model; Zealot can use several WP weapons, so the dual-hammer skeleton vocab is reusable here. |
| BS-B3 | dr_dual_wield_hammers [SUPERSEDED] | Bardin: Dual Hammers | ~~Saltzpyre Dual Skull-Splitters~~ (removed) | melee | **SUPERSEDED - REMOVED from non-WP Saltzpyre entirely: redundant with the Dual Skullsplitters (wh_dual_hammer) those careers already have. CHANGELOG v0.12.164-dev; regression test no_dwarf_dual_hammers_on_saltzpyre. Key de-backticked so the gate reads this row as inactive.** Original note (history): Same wh_dual_hammer 3P target as BS-B2 - dual-blunt vocab fits. |
| BS-B4 | `dr_rakegun` | Bardin: Grudge-Raker | Saltzpyre Volley Crossbow (`wh_crossbow_repeater`) | ranged | Volley Crossbow is the closest Saltzpyre native to a multi-projectile spread-fire weapon. |
| BS-B5 | `dr_drake_pistol` | Bardin: Drakefire Pistols | Saltzpyre Brace of Pistols (`wh_brace_of_pistols`) | ranged | Dual-pistol stance; brace-of-pistols 3P vocab fits the two-handed pistol presentation. |
| BS-B6 | `dr_drakegun` | Bardin: Drakegun | Saltzpyre Volley Crossbow (`wh_crossbow_repeater`) | ranged | Sustained-projection weapon; no native flamethrower 3P on Saltzpyre. Volley Crossbow shoulder-mount is the least-bad approximation. |
| BS-B7 | `dr_steam_pistol` | Bardin: Masterwork Pistol | Saltzpyre Repeating Pistol (`wh_repeating_pistols`) | ranged | Single-shot precision pistol; Saltzpyre's Repeating Pistol vocab works for the one-handed pistol stance + recoil. |
| BS-B8 | `dr_deus_01` | Bardin: Trollhammer Torpedo | Saltzpyre Crossbow (`wh_crossbow`) | ranged | Heavy two-handed shoulder-fired projectile; Crossbow is the only Saltzpyre two-handed-ranged 3P vocab available. |

Implementation note: Wave 2 anim redirects may be needed for BS-B1 (throwing
axes wind-up/release events have no Saltzpyre native), BS-B4/BS-B6 (rakegun
/ drakegun spread-fire and sustained-projection don't map cleanly to volley
crossbow trigger events), and BS-B8 (trollhammer reload/blast vs crossbow
single-shot). BS-B2/BS-B3 dual-blunt route through `wh_dual_hammer` should
fall through cleanly; BS-B5/BS-B7 brace + repeating pistol native event
vocab should cover the single/dual-pistol cases.

### Kerillian weapons → Saltzpyre non-WP (Batch C, 2026-05-31)

Routes 9 WE source weapons (6 melee + 3 ranged) to the three non-WP Saltzpyre
careers. Source target overview (3P targets to be wired in Wave 2):

**Batch C SKIP decisions:**

| # | Skipped | Reason |
|---|---|---|
| C-skip-1 | `we_crossbow_repeater` (Kerillian: Volley Crossbow) | Already present in `wh_captain` / `wh_bountyhunter` / `wh_zealot` rows of `weapon_unlock_map` natively (verified at wt_unlock_data.lua line 116-118). Existing `unlock_wh_<career>_we_crossbow_repeater` checkboxes + loc keys cover it. No new entry needed. |

**Batch C ADD decisions (9 weapons × 3 careers = 27 entries):**

| # | Source weapon (key) | Display name | Target (3P) | Class |
|---|---|---|---|---|
| C1 | `we_1h_axe` | Kerillian: 1H Axe | Saltzpyre 1H Axe (`wh_1h_axe`) | melee |
| C2 | `we_2h_axe` | Kerillian: Glaive | **WP 2H Hammer / Greathammer (`wh_2h_hammer`)** — user override 2026-05-31 (was `wh_2h_sword` in initial bake) | melee |
| C3 | `we_2h_sword` | Kerillian: Elf 2H Sword | Saltzpyre 2H Sword (`wh_2h_sword`) | melee |
| C4 | `we_dual_wield_daggers` | Kerillian: Dual Daggers | Saltzpyre Axe and Falchion (`wh_dual_wield_axe_falchion`) | melee |
| C5 | `we_dual_wield_swords` | Kerillian: Dual Swords | Saltzpyre Axe and Falchion (`wh_dual_wield_axe_falchion`) | melee |
| C6 | `we_dual_wield_sword_dagger` | Kerillian: Sword & Dagger | Saltzpyre Axe and Falchion (`wh_dual_wield_axe_falchion`) | melee |
| C7 | `we_shortbow` | Kerillian: Shortbow | **Saltzpyre Volley Crossbow (`wh_crossbow_repeater`) + 3P MODEL swap to volley crossbow unit** — user override 2026-05-31 (was `wh_crossbow` in initial bake) | ranged |
| C8 | `we_shortbow_hagbane` | Kerillian: Hagbane Shortbow | **Saltzpyre Volley Crossbow (`wh_crossbow_repeater`) + 3P MODEL swap to volley crossbow unit** — user override 2026-05-31 | ranged |
| C9 | `we_deus_01` | Kerillian: Moonfire Bow | Saltzpyre Crossbow (`wh_crossbow`) | ranged |

**Clarification on C-skip-1 (`we_crossbow_repeater`)** — user pointed out 2026-05-31 that the Elf Repeater Crossbow is NOT functionally identical to Saltzpyre's Volley Crossbow (elf = faster, vertical spread; Saltzpyre = slower, horizontal). However it IS already in Saltzpyre's native unlock_map so the toggle is already available. The runtime redirect `_anim_redirect.to_repeating_crossbow → to_repeating_crossbow_elf` already maps Saltzpyre wielding the elf repeater to use his Volley Crossbow animations, which the user notes "should work almost perfectly." No code action needed for this port.

Implementation note: Wave 2 anim redirects will be needed for the 3 ranged
ports (C7-C9) — bow `draw_bow` / `attack_shoot_fast` vocab doesn't match
Saltzpyre's crossbow `to_zoom` / `attack_shoot` vocab; same remap shape as
Example B / C in `CROSS_CHARACTER_PORT_RECIPE.md` (longbow → crossbow on
Saltzpyre, shipped v0.12.44-dev). The 6 melee ports (C1-C6) route through
existing Saltzpyre 1H-axe / 2H-sword / dual-wield-axe-falchion event vocab
and should fall through cleanly without explicit redirects, modulo per-
action `*_fast` / `*_charged` substitutions if encountered.

### Sienna weapons → Saltzpyre non-WP (Batch D, 2026-06-03)

Routes 8 BW source weapons (4 melee + 4 ranged) to the three non-WP Saltzpyre
careers (`wh_captain`, `wh_bountyhunter`, `wh_zealot`). Source target overview
(3P targets to be wired in Wave 2):

**Batch D SKIP decisions:**

| # | Skipped | Reason |
|---|---|---|
| D-skip-1 | `bw_1h_flail_flaming` (Sienna: Flaming Flail) | User decision 2026-06-03: very similar to Saltzpyre's own flail. Saltzpyre natively carries `es_1h_flail` in his unlock_map; the Sienna flaming flail is functionally redundant. |
| D-skip-2 | `bw_sword` (Sienna: Sword) | Analogous to `wh_1h_falchion` (Saltzpyre native 1H sword-class). No functional distinction worth a duplicate port. |

**Batch D ADD decisions (8 weapons × 3 careers = 24 entries):**

| # | Source weapon (key) | Display name | Target (3P) | Class | User note |
|---|---|---|---|---|---|
| D1 | `bw_1h_mace` | Sienna: Mace | Saltzpyre 2H Hammer (`wh_2h_hammer`) | melee | User: Sienna's mace is held 2-handed; use WP 2H hammer animations. |
| D2 | `bw_dagger` | Sienna: Dagger | Saltzpyre Rapier (`wh_fencing_sword`) | melee | Rapier is the closest stab/thrust vocab on Saltzpyre. |
| D3 | `bw_flame_sword` | Sienna: Flame Sword | Saltzpyre Falchion (`wh_1h_falchion`) | melee | 1H sword-class; falchion is the natural fit. |
| D4 | `bw_ghost_scythe` | Sienna: Ensorcelled Reaper | Saltzpyre 2H Hammer (`wh_2h_hammer`) | melee | User: just like the Sienna mace — WP 2H Hammer. |
| D5 | `bw_skullstaff_beam` | Sienna: Beam Staff | Saltzpyre Falchion (`wh_1h_falchion`) | ranged | User: all staves to falchion. |
| D6 | `bw_skullstaff_fireball` | Sienna: Fireball Staff | Saltzpyre Falchion (`wh_1h_falchion`) | ranged | User: all staves to falchion. |
| D7 | `bw_skullstaff_flamethrower` | Sienna: Flamestorm Staff | Saltzpyre Falchion (`wh_1h_falchion`) | ranged | User: all staves to falchion. |
| D8 | `bw_skullstaff_geiser` | Sienna: Conflagration Staff | Saltzpyre Falchion (`wh_1h_falchion`) | ranged | User: all staves to falchion. |

Implementation note: Wave 2 anim redirects NOT YET WIRED — separate fix pass.
Staves routed through `wh_1h_falchion` will need bespoke wield/attack redirects
since the falchion 3P vocab doesn't author cast/charge/beam events. The two
mace-family ports (D1/D4) route through native `wh_2h_hammer` 2H-blunt vocab
and should fall through cleanly for the swing animations; `bw_dagger` → Rapier
maps cleanly for thrust + slash actions modulo per-action `*_fast` / `*_charged`
substitutions if encountered.

### Batch E + Shield-Combos Override (2026-06-04)

Final non-WP receiver batch: closes out Batch E (the 5 source weapons
previously skipped because the receiver-side animation target was undecided)
plus retroactively adds 7 shield-combo source weapons. The shield-combo block
reverses prior SKIP decisions (Batch A SKIP rows BS-A-skip-2/3/4 above and
the KS-batch shield rows KS6-KS9 flagged earlier in this section) — user
decision 2026-06-04: **for all shielded source weapons use Saltzpyre's axe
and falchion animations**, i.e. target `wh_dual_wield_axe_falchion`. That
target's 3P vocab is the closest non-WP Saltzpyre body has to a shield-
stance presentation; the off-hand slot of the axe-and-falchion combo carries
the shield while the right hand carries the swap-in weapon.

**Shipped — Batch E wired rows (4 weapons × 3 careers = 12 entries):**

| # | Source weapon (key) | Display name | Target (3P) | Class |
|---|---|---|---|---|
| E1 | `bw_skullstaff_spear` | Sienna: Bolt Staff | Saltzpyre Falchion (`wh_1h_falchion`) | ranged |
| E2 | `bw_necromancy_staff` | Sienna: Soulstealer Staff | Saltzpyre Falchion (`wh_1h_falchion`) | ranged |
| E3 | `bw_deus_01` | Sienna: Coruscation Staff | Saltzpyre Falchion (`wh_1h_falchion`) | ranged |
| E4 | `we_javelin` | Kerillian: Javelin | Saltzpyre 1H Axe (`wh_1h_axe`) | ranged |

**To ADD — pending Batch E row:**

| # | Source weapon (key) | Display name | Target (3P) | Class |
|---|---|---|---|---|
| E5 | `we_life_staff` | Kerillian: Deepwood Staff | Saltzpyre Falchion (`wh_1h_falchion`) | ranged |

**Shipped — Shield-Combos Override (6 weapons × 3 careers = 18 entries):**

| # | Source weapon (key) | Display name | Target (3P) | Class | Supersedes |
|---|---|---|---|---|---|
| SHO1 | `es_mace_shield` | Kruber: Mace and Shield | `wh_dual_wield_axe_falchion` | melee | KS6 / BS-A-skip-1 |
| SHO2 | `es_sword_shield` | Kruber: Sword and Shield | `wh_dual_wield_axe_falchion` | melee | KS7 / BS-A-skip-2 |
| SHO3 | `es_sword_shield_breton` | Kruber: Bretonnian Sword and Shield | `wh_dual_wield_axe_falchion` | melee | KS8 / BS-A-skip-3 |
| SHO4 | `es_deus_01` | Kruber: Spear and Shield (CW deus) | `wh_dual_wield_axe_falchion` | melee | KS9 / BS-A-skip-4 |
| SHO5 | `dr_shield_axe` | Bardin: Axe and Shield | `wh_dual_wield_axe_falchion` | melee | (new — never queued) |
| SHO7 | `we_1h_spears_shield` | Kerillian: Spear and Shield | `wh_dual_wield_axe_falchion` | melee | (new — never queued) |

SHO6 (`dr_shield_hammer`, Bardin: Hammer and Shield) is retired by #594.
Saltzpyre keeps Kruber's `es_mace_shield`; the returned unlock map explicitly
removes Bardin's analogous weapon for all three non-Warrior-Priest careers.

**Shipped — inventory-wiring reconciliation (2026-08-02):**

The checker verifies each row below is present for all three non-Warrior-Priest
Saltzpyre careers in `weapon_unlock_map`, has its availability checkbox, and
has its localization key. These are live ports omitted from the earlier batch
tables; this reconciliation records existing wiring without inventing new
animation-target decisions.

| Source weapon (key) | Display name |
|---|---|
| `bw_1h_crowbill` | Sienna: Crowbill |
| `es_1h_flail` | Kruber: Flail |
| `es_1h_mace` | Kruber: Mace |
| `es_1h_sword` | Kruber: Sword |
| `es_2h_heavy_spear` | Kruber: Tuskgor Spear |
| `es_halberd` | Kruber: Halberd |
| `es_longbow` | Kruber: Longbow |
| `we_1h_sword` | Kerillian: Sword |
| `we_crossbow_repeater` | Kerillian: Volley Crossbow |
| `we_longbow` | Kerillian: Longbow |
| `we_spear` | Kerillian: Spear |

**Current reconciled Batch E + Shield-Combos state:** 10 weapons are fully
wired across the three non-Warrior-Priest careers, `we_life_staff` remains a
documented pending row, and `dr_shield_hammer` is retired by #594.

Implementation note: Wave 2 anim redirects NOT YET WIRED — separate fix
pass. The 5 Batch E ranged ports (E1-E5) need bespoke redirects: staves
through `wh_1h_falchion` will need cast/charge/beam wield-vocab synthesis
(same problem class as Batch D staves); javelin through `wh_1h_axe` needs
windup/throw event mapping with no native Saltzpyre thrown-weapon vocab;
Deepwood through `wh_1h_falchion` shares the staff-cast remap problem. The
7 shield-combo melee ports (SHO1-SHO7) route through native
`wh_dual_wield_axe_falchion` event vocab — should fall through cleanly
for the swing/block animations, but the shield-unit attachment in 3P will
need a model-swap dispatcher (Wave 3) mirroring the existing brace-of-
pistols / griffon-foot model-swap pattern documented in
`CROSS_CHARACTER_PORT_RECIPE.md`.

## Receiver: Warrior Priest

Bow/crossbow/longbow/firearm ports are FORBIDDEN per
`feedback_vt2_no_bows_on_warrior_priest.md` (WP's body authors no
`to_longbow` / `to_crossbow` / `to_*pistol*` / `to_handgun` events).

**Shipped — inventory-wiring reconciliation (2026-08-02):**

| Source weapon (key) | Display name | Reconciliation evidence |
|---|---|---|
| `es_1h_flail` | Kruber: Flail | Present in `wh_priest` unlocks with checkbox and localization. |

## Receiver: Bardin

**Shipped — inventory-wiring reconciliation (2026-08-02):**

The checker verifies every row on Ranger Veteran, Ironbreaker, Slayer, and
Outcast Engineer across the unlock map, checkbox definitions, and localization.

| Source weapon (key) | Display name |
|---|---|
| `bw_1h_crowbill` | Sienna: Crowbill |
| `es_1h_sword` | Kruber: Sword |
| `es_handgun` | Kruber: Handgun |
| `we_1h_sword` | Kerillian: Sword |
| `wh_1h_falchion` | Saltzpyre: Falchion |

## Receiver: Kerillian

**Shipped — inventory-wiring reconciliation (2026-08-02):**

The checker verifies every row on Waystalker, Handmaiden, Shade, and Sister of
the Thorn across the unlock map, checkbox definitions, and localization.

| Source weapon (key) | Display name |
|---|---|
| `es_1h_mace` | Kruber: Mace |
| `es_2h_sword` | Kruber: Greatsword |
| `es_deus_01` | Kruber: Spear and Shield |
| `es_longbow` | Kruber: Longbow |
| `wh_crossbow_repeater` | Saltzpyre: Volley Crossbow |

## Receiver: Sienna

Currently no cross-character ports. User to decide whether to add any.

(Filled in during walkthrough.)

---

## Bake status

| Date | Version | Batches wired (unlock_map + checkboxes + loc keys) |
|---|---|---|
| 2026-07-17 | (doc reconciliation) | **SUPERSEDED / REMOVED ROWS marked inactive** so the check_decisions_wired gate stops reading them as live "To ADD". Six Bardin-source rows were wired-then-removed by later shipped decisions and are guarded by live regression tests; their decision-table rows above are annotated SUPERSEDED (weapon keys de-backticked to plain text so the wiring checker, which keys off backticked weapon keys, treats them as inactive). Rows: [Kruber] dr_dual_wield_axes (B-dualaxes) - #582, v0.12.226-dev, test issue582_native_dual_axes_cwv_ownership_boundary, tombstone _wt_availability.lua; [Kruber] dr_dual_wield_hammers (B-dualhammers) - Bardin batch CORRECTION (this doc), replaced by wh_dual_hammer; [Saltzpyre non-WP] dr_1h_axe + dr_1h_hammer (BS-A1/BS-A2) - #187, v0.12.173-dev, test no_redundant_bardin_1h_on_saltzpyre; [Saltzpyre non-WP] dr_dual_wield_axes (BS-B2) - #582, v0.12.226-dev, test issue582_native_dual_axes_cwv_ownership_boundary; [Saltzpyre non-WP] dr_dual_wield_hammers (BS-B3) - v0.12.164-dev, test no_dwarf_dual_hammers_on_saltzpyre. Bardin and Kerillian keep these natively. No code change; doc-only reconciliation. |
| 2026-06-19 | v0.12.132-dev | **Wave 2 bulk wield-encode — anim-picker "redirect to" dropdown removal.** 132 cross-character port wield decisions across 72 source templates wired into `_WIELD_ANIM_CAREER_3P_PATCHES_BULK` (weapon_tweaker.lua), generated from this doc's receiver walk-throughs. Every target's wield event was VERIFIED against the vanilla weapon template's `wield_anim` by a 3-receiver verification pass — which caught doc-shorthand errors: `to_2h_axe`→`to_2h_axe_we`, `to_dual_wield_swords`→`to_dual_swords`, `to_dual_wield_sword_dagger`→`to_dual_sword_dagger`, `to_1h_mace`→`to_1h_hammer`. The dev anim-picker now DROPS the redirect dropdown for every encoded port and filters the per-attack `anim_event_3p` dropdowns to the target's vocab. Picker made **receiver-aware** (`_WIELD_TARGET_BY_RECEIVER` keyed by career prefix es/we/wh, checked before the flat map) to resolve the 3-way `to_1h_sword` collision (Empire Sword / Elf Sword / Falchion) plus `to_1h_axe` and `to_1h_hammer`. NOTE: setting `wield_anim_career_3p[career]` also wires the in-mission wield stance, so these ports now actually render as their target weapon in 3P (per-attack tuning still happens in the picker). DEFERRED (still show dropdowns): 4 Saltzpyre Volley-Crossbow ports (`dr_rakegun`/`dr_drakegun`/`we_shortbow`/`we_shortbow_hagbane` — wh-body stance `to_repeating_crossbow` vs `..._elf` needs an in-game probe), `we_javelin`/`we_life_staff` on Kruber (doc-pending/experimental), and native fall-through ports. Covers Kruber / Kerillian / Saltzpyre-non-WP receivers; Bardin / WP / Sienna receiver sections remain empty. |
| 2026-06-04 | v0.12.110-dev | **Saltzpyre (non-WP) receiver** Batch E remaining + Shield-Combos Override: 12 source weapons across 3 non-WP careers. Batch E (5 ranged): bw_skullstaff_spear (Bolt Staff), bw_necromancy_staff (Soulstealer Staff), bw_deus_01 (Coruscation Staff), we_javelin, we_life_staff (Deepwood Staff) — all routed to `wh_1h_falchion` except `we_javelin` routed to `wh_1h_axe`. Shield-Combos Override (7 melee): es_mace_shield, es_sword_shield, es_sword_shield_breton, es_deus_01, dr_shield_axe, dr_shield_hammer, we_1h_spears_shield — all routed to `wh_dual_wield_axe_falchion`. SUPERSEDES Batch A SKIP rows BS-A-skip-2/3/4 and Batch KS FLAG rows KS6/KS7/KS8/KS9 (user reversed "non-WP has no shield stance" reasoning). = 36 new entries. Wave 2 anim redirects (staff-cast/charge for the 3 staves + Deepwood through `wh_1h_falchion`; javelin throw-vocab through `wh_1h_axe`) + Wave 3 model-swap dispatcher for shield off-hand attachment on `wh_dual_wield_axe_falchion` NOT YET WIRED — separate fix pass. |
| 2026-06-03 | v0.12.109-dev | **Saltzpyre (non-WP) receiver** Sienna batch D1-D8: 8 BW source weapons across 3 non-WP careers (bw_1h_mace, bw_dagger, bw_flame_sword, bw_ghost_scythe melee; bw_skullstaff_beam, bw_skullstaff_fireball, bw_skullstaff_flamethrower, bw_skullstaff_geiser ranged); SKIPPED bw_1h_flail_flaming (~ Saltzpyre native es_1h_flail) and bw_sword (~ wh_1h_falchion native 1H sword-class). 4 melee + 4 ranged. = 24 new entries. Wave 2 anim redirects (Saltzpyre `wh_1h_falchion` staff-cast/charge for the 4 staves; `wh_2h_hammer` for bw_1h_mace + bw_ghost_scythe; `wh_fencing_sword` for bw_dagger) NOT YET WIRED — separate fix pass. |
| 2026-05-31 | v0.12.103-dev | **Kerillian receiver** Sienna batch SiK1-SiK14: 12 BW source weapons across 4 careers (bw_1h_crowbill, bw_1h_flail_flaming, bw_dagger, bw_flame_sword, bw_ghost_scythe melee; bw_skullstaff_beam/fireball/flamethrower/geiser/spear + bw_necromancy_staff + bw_deus_01 ranged); SKIPPED bw_1h_mace (~ es_1h_mace already on Kerillian) and bw_sword (~ we_1h_sword). = 48 new entries. **Saltzpyre (non-WP) receiver** Kruber batch KS1/KS3/KS4/KS5/KS10/KS11/KS12: 7 ES source weapons across 3 non-WP careers (es_bastard_sword, es_2h_sword_executioner, es_2h_hammer, es_dual_wield_hammer_sword melee; es_blunderbuss, es_handgun, es_repeating_handgun ranged); SKIPPED KS2 es_2h_sword (~ wh_2h_sword native); FLAGGED KS6 es_mace_shield / KS7 es_sword_shield / KS8 es_sword_shield_breton / KS9 es_deus_01 (shield combos — non-WP careers lack native shield-stance support; user to revisit). = 21 new entries. **Saltzpyre (non-WP) receiver** Kerillian batch C1-C9: 9 WE source weapons across 3 non-WP careers (we_1h_axe, we_2h_axe, we_2h_sword, we_dual_wield_daggers, we_dual_wield_swords, we_dual_wield_sword_dagger melee; we_shortbow, we_shortbow_hagbane, we_deus_01 ranged); SKIPPED we_crossbow_repeater (already native on non-WP rows). = 27 new entries. Wave 2 anim redirects (Saltzpyre `to_crossbow` for KS10/KS11 + repeater-pistol for KS12; Saltzpyre `to_crossbow` for C7/C8/C9 bow→crossbow remap) NOT YET WIRED — separate fix pass. |
| 2026-05-30 | v0.12.103-dev | **Kruber receiver**: Bardin batch (B-cog, B-pick, B-dualaxes, B-shieldaxe, B-throw, B-drakepistol, B-drakegun, B-steampistol, B-deus, BONUS wh_1h_axe; B-dualhammers removed per correction). Kerillian batch (we_1h_axe, we_2h_axe, we_dual_wield_daggers, we_dual_wield_swords, we_dual_wield_sword_dagger, we_deus_01, we_shortbow, we_shortbow_hagbane, we_crossbow_repeater). Saltzpyre batch (wh_dual_hammer, wh_2h_hammer, wh_fencing_sword, wh_crossbow_repeater, wh_deus_01). WP batch (wh_flail_shield, wh_hammer_book). Sienna batch (bw_1h_mace, bw_dagger, bw_flame_sword, bw_ghost_scythe, bw_skullstaff_beam, bw_skullstaff_fireball, bw_skullstaff_flamethrower, bw_skullstaff_geiser, bw_skullstaff_spear, bw_necromancy_staff, bw_deus_01). **Kerillian receiver**: Kruber batch (es_1h_flail, es_2h_hammer, es_2h_heavy_spear, es_2h_sword_executioner, es_bastard_sword, es_dual_wield_hammer_sword, es_halberd, es_mace_shield, es_sword_shield, es_sword_shield_breton, es_blunderbuss, es_handgun, es_repeating_handgun). Bardin batch (wh_1h_axe BONUS, dr_1h_hammer, dr_1h_throwing_axes, dr_2h_axe, dr_2h_cog_hammer, dr_2h_pick, dr_crossbow, dr_deus_01, dr_drake_pistol, dr_drakegun, dr_dual_wield_axes, dr_dual_wield_hammers, dr_rakegun, dr_shield_axe, dr_steam_pistol). **SKIPPED**: `we_javelin` on Kruber (EXPERIMENTAL), `we_life_staff` on Kruber (PENDING user decision). Wave 2 (anim redirects / `_career_anim_redirect` / `_WIELD_ANIM_CAREER_3P_PATCHES`) and Wave 3 (3P model/offhand swap dispatchers for drakefire, griffon-foot, brace mirror) NOT YET WIRED — separate fix pass owned by the lead. |
