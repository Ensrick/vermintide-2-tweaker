# Code Review: character_weapon_variants

**Latest pass:** 2026-05-23 (refresh)
**Prior pass:** 2026-05-01 (snapshot at v0.1.56-dev — **SUPERSEDED**)
**Current version:** v0.1.347-dev
**Audit verdict:** IN-DEV (shipping audits #9 and #13, active iteration on Old Musket/Tuskgor Javelin)

> **Header re-stamped 2026-05-29; body findings predate this version and may be stale — see GitHub Issues for current state.** This review's body was written against `v0.1.331-dev`; the header version was corrected to match disk (`v0.1.347-dev`) on 2026-05-29 but the body below was NOT re-reviewed.

---

## Executive Summary

CWV has matured v0.1.56-dev to v0.1.331-dev over 22 days, accumulating 275 versions and a comprehensive recipe library (RECIPES.md, DEFINITION_OF_DONE.md, ANIMATION_FIX_PLAYBOOK.md, DEVELOPMENT.md). The mod registers 20+ cross-character weapon variants via MoreItemsLibrary and ships with extensive documentation to prevent the recurring bug class where "looks right locally, breaks on equip/fire/forge/preview/dual-wield."

**Critical issue:** The main source file (`character_weapon_variants.lua`) reaches **8,800 lines** — **3.5× the 2,500-line hard limit** per PROJECT_STANDARDS §2.1. This is the single largest Lua file in the repo and a refactoring candidate.

**Strengths:**
- Definition of Done gate + RECIPES.md documentation discipline prevents regressions
- Variant authoring is proceduralized: every archetype has a recipe + canonical shipped example
- 45 hooks + 30 chat commands; all follow documented patterns (lazy string-form resolution, backward-compatible gates)
- No forward-reference bugs, no bare-global namespace pollution (fixed in audit #9, see below)

---

## Recent Audits & Cleanups (v0.1.330–v0.1.331)

### Audit #9 (v0.1.330, 2026-05-22): Bare-global → local forward-decl refactor

Converted 22 bare-global assignments (`_foo = function...` without `local` keyword) to canonical `local _foo` forward declarations. **Scope:** lines ~2702–2850 (Old Musket section), 9 functions:
- `_cwv_musket_pool_cap`, `_cwv_musket_sync_pool`, `_cwv_musket_register_ammo_ext`
- `_track_old_musket_unit`, `_apply_old_musket_textures`, `_apply_old_musket_transform`
- `_spawn_old_musket_fx_proxy`, `_destroy_old_musket_fx_proxy`, `_reapply_old_musket_transforms_all`

**Why it mattered:** All call sites fire from hook bodies at runtime AFTER module load, so functionally safe today. But bare assignments pollute the Lua global namespace and create forward-reference risk if any caller ever migrates to module-load time. Per `feedback_lua_forward_reference.md`, five crash bugs in this codebase trace back to this pattern.

**Status:** Shipped and verified. No regressions.

### Audit #13 (v0.1.331, 2026-05-22): Removed unused `mod.weapon_analogues` table

Deleted two vestigial exports (lines 74–81) with zero external consumers:
- `mod.weapon_analogues` — cross-character weapon identity pairs table
- `mod.get_analogues(item_key)` — getter function

Both were documented in CHANGELOG v0.1.45 as "consumed by cosmetics_tweaker's LA bridge" but that consumer never shipped. Exhaustive grep (repo-wide + sibling-mod manifest scan) confirmed zero call sites.

**Status:** Shipped. Repo scanned for orphaned references; none found.

---

## Architecture Overview

### Variant Authoring Pipeline

| Stage | Location | Artifact |
|---|---|---|
| **Author & spec** | `_variant_definitions` (lines ~86–600) | Def table: item_key, base_weapon, careers, right/left_hand_unit, rarity, template |
| **Validate** | `DEFINITION_OF_DONE.md` | Universal checklist + 9 trait-gated sub-checklists (G-DUAL, G-RANGED, G-3P-ANIM, etc.) |
| **Proceduralize** | `RECIPES.md` | Decision tree (A1–C1) + copy-paste recipes + add-ons (stat-mod, damage-swap, inverse-hand) |
| **Build & deploy** | `VMBLauncher.exe all <mod>` | VMB build → bundleV2/, copy to Workshop + PC-B, full game restart |
| **Reference** | `DEVELOPMENT.md` + `ANIMATION_FIX_PLAYBOOK.md` | Technical why: rarity, skin system, 3P-only rule, closed-vocab procedure |

### Major Subsystems

**Old Musket stance-toggle (v0.1.272+, ongoing):** Third-party Lathander CC-BY 4.0 model. Stance switch via destroy_slot → add_equipment → wield cycle + `BackendUtils.get_item_template` hook + ammo persistence. Per-template transform overrides (4 buckets: 1P-ranged, 1P-melee, 3P-ranged, 3P-melee). Eight live-tuning chat commands (`/cwv_om_pos_*`, `/cwv_om_rot_*`, etc.).

**Tuskgor Javelin projectile system (v0.1.65+, ongoing):** Elf javelin moveset grafted onto boar-spear mesh. Runtime-hidden 3P spare (v0.1.324). Link_pickup respawn on impact. 7-layer thrown weapon recipe per RECIPES.md.

**Dual-wield architecture:** Requires `_force_display_unit` with correct rig (`display_dual_weapons` / `display_dual_axes` / `display_dual_hammers`) per J_LEFTWEAPONATTACH_INVESTIGATION.md (20-version post-mortem of rig mismatches).

**Custom illusion injection:** Three-table system (ItemMasterList + WeaponSkins.skins + skin_combinations) + `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins` hook + Localize hook.

### File Size Crisis

| Region | Lines | Status |
|---|---|---|
| Variant defs (20+ variants) + utilities | 530+500 | ✓ (core payload) |
| Old Musket section (stance-toggle, transforms, FX, ammo) | 2,500 | ↳ **Candidate for `_variants/old_musket.lua`** |
| Tuskgor Javelin + Brace-Repeater | 1,200 | ↳ **Candidate for `_variants/javelin.lua` + `_variants/brace.lua`** |
| Dual-wield illusion registrars | 800 | ↳ **Candidate for `_variants/dual_illusions.lua`** |
| Cross-access animation remap | 600 | ↳ **Candidate for `_animation_remaps.lua`** |
| Hook registrations (45 total) + commands (30 total) | 3,600 | ↳ Candidates for `_hooks.lua` + `_commands.lua` split |
| **Total** | **8,800** | **3.5× limit** |

---

## Concerns with Line References

### P1: File Size

Exceeds **2,500-line hard limit** per PROJECT_STANDARDS §2.1. Single 8,800-line file creates per-file cognitive load (forward-decl searches hit multiple matches), refactoring risk, and VMF hook-ordering edge-case fragility.

**Proposed refactor plan:**
```
character_weapon_variants/scripts/mods/character_weapon_variants/
├── character_weapon_variants.lua (core: ~3,000 lines)
├── _variant_dsl.lua (reusable: ~500 lines — _clone_damage_profile, _resolve_field, etc.)
├── _variants/
│   ├── old_musket.lua (~2,500 lines)
│   ├── tuskgor_javelin.lua (~1,200 lines)
│   ├── brace_repeater.lua (~600 lines)
│   ├── dual_illusions.lua (~800 lines)
│   └── animation_remaps.lua (~600 lines)
└── (optional: _hooks/, _commands/ further split)
```

**Trade-off:** This is a **medium refactor** that shouldn't ship in v0.1.331 but should trigger on **v0.1.350+** when the next audit lands. Audits #9 and #13 show the file is at maintainability ceiling.

### P1 (latent): Offset double-application in inventory previewer

Both `HeroPreviewer._spawn_item` + `MenuWorldPreviewer._spawn_item` hooks registered. MenuWorldPreviewer calls `super._spawn_item`, so HeroPreviewer hook fires inside the super-call, then MenuWorldPreviewer hook fires **after**. Result: `_cwv_spawn_item_post` runs **twice** per spawn for MenuWorldPreviewer instances.

**Current safety:** `_apply_scale` is idempotent (absolute `Unit.set_local_scale`). `_apply_offset` is **additive** (reads current position, adds offset). No current variant uses `right_hand_offset` / `left_hand_offset`, so **dormant bug**.

**Action:** When first offset variant ships, either drop one hook, make offset idempotent (track baseline per unit), or guard with per-spawn flag.

### P2: Recent audit cleanups

**Audit #9:** Converted bare-globals. Verified no regressions; all call sites fire at runtime after module load.
**Audit #13:** Removed unused exports. Repo scanned; zero orphaned references.

Both shipped clean. No latent issues surfaced.

---

## Code Quality Findings

**Forward-reference audit (per DEFINITION_OF_DONE.md §U-7):** Every variant definition verified to reference only functions defined above. No forward-ref bugs. The 9 functions converted in audit #9 already had this property (all called from hook bodies at runtime), so audit #9 closed one potential pitfall retroactively.

**Hook patterns:** All 45 hooks follow documented guidance:
- String-form lazy resolution where required (StateInGameRunning, BackendInterface*, Managers.*, Unit, World)
- Table-form only for non-hookable (BackendUtils, NetworkLookup)
- No `BackendUtils.can_wield_item` hook (correctly avoided; use ItemMasterList.can_wield directly per CLAUDE.md)
- `mod:hook_safe` for advisory firing vs. `mod:hook` for wrapping + override

**Variant catalog:** 20+ shipping variants, all walk the DoD gate. Variants marked in CHANGELOG with `**DoD:** <gates walked>` footer per DEFINITION_OF_DONE.md requirement.

---

## What's Changed Since v0.1.56-dev (2026-05-01 baseline)

**Documentation explosion (the main delta):**
- RECIPES.md (decision tree + 7 copy-paste recipes + 8 add-ons)
- DEFINITION_OF_DONE.md (universal checklist + 9 trait-gated sub-checklists)
- DEVELOPMENT.md (rarity, skin system, 3P-only anim rule, base-template patching, Frankenstein weapons)
- ANIMATION_FIX_PLAYBOOK.md (9-step closed-vocabulary procedure + worked example)
- J_LEFTWEAPONATTACH_INVESTIGATION.md (20-version post-mortem, dual-rig rule)
- CHANGELOG.md now carries DoD footer on every variant entry

**Variant count:** Grew from ~8 variants (v0.1.56) to 20+ variants (150% growth).

**Code quality:** Audit #9 (bare-globals) + Audit #13 (unused exports) completed, both shipped and verified clean.

**Known issues tracked:** Old Musket 3P-RANGED stance transform baked (v0.1.325). Tuskgor Javelin stick-depth TODO reverted pending axis-identification. Offset double-application latent bug → gate when first offset variant lands.

---

## Top 3 Concerns (Priority Order)

1. **File size (P1):** 8,800 lines is 3.5× the hard limit. Refactor plan drafted above; should trigger on next audit (v0.1.350+).

2. **Offset double-application latent bug (P1):** MenuWorldPreviewer.sub._spawn_item fires twice. Dormant because no variant uses offsets yet; gate the fix when first offset variant ships.

3. **Architecture clarity (P3):** CWV owns new items (System B — template clone) but cross-access variants on vanilla shared templates use System A (runtime hook). Two parallel systems work, but future migrations require clear documentation in ANIMATION_FIX_PLAYBOOK.md.

---

## Verdict

**IN-DEV.** Mature for active iteration. Audits #9 and #13 landed cleanly. Variant authoring pipeline is well-documented and gated. The single actionable item is file-size refactoring, which should be scheduled for **v0.1.350+** (no urgency for v0.1.331).

**Summary stats:**
- 8,800 source lines (3.5× limit)
- 20+ variants
- 45 hooks
- 30 chat commands
- 9 trait-gated DoD checklists
- Zero forward-ref bugs
- Two recent audits shipped clean

**Word count:** 1,670 words (target 1,500–2,500 ✓)
