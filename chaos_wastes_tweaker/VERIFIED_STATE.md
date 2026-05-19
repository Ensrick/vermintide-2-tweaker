# Chaos Wastes Tweaker — Verified State

**Last updated:** 2026-05-19
**Source version:** v0.7.64 (lua)

What this doc is: ct's features and behaviors backed by **evidence** — CHANGELOG entries, source-line refs, and/or memory entries. **No speculation in this doc.** If a claim can't be tied to evidence, it belongs in `AUDIT_FINDINGS.md`, not here.

---

## Features verified working

### Ghost-scythe bot crash fix (cross-career weapon spawn safety)
- **What:** Prevents `Unit not found wpn_bw_ghost_scythe_01_3p` (and equivalents for other DLC-career weapons) when a bot equipped with a DLC career's weapon spawns into a CW run.
- **Evidence:**
  - Implementation: `chaos_wastes_tweaker.lua:768-825` — `GearUtils.create_equipment` hook with two-layer fix (career_name recovery from `inventory_system._career_name`; pre-resolved `override_item_units`).
  - Recipe: `weapon_tweaker/CHANGELOG.md` v0.12.23-v0.12.25.
  - Memory: `feedback_search_changelog_for_known_crashes.md`.
  - Bad-workaround removal documented: `_adventure_pool.lua:342-346`.

### Boon disable
- **What:** Host disables any of 172 CW boons from rolling at shrines / chests / altars / Bel'akor's Temple.
- **Evidence:**
  - Implementation: `chaos_wastes_tweaker.lua:139-217` — save-and-restore mutation of `DeusPowerUpsArray` / `*ByRarity` around `generate_random_power_ups`.
  - CHANGELOG: v0.2.5-dev (2026-04-28) — "Added: Disabled Boons" (all 172 enumerated).

### Starting boons
- **What:** Host grants any of 172 boons as starting boons at the beginning of a CW run.
- **Evidence:**
  - Implementation: `chaos_wastes_tweaker.lua` `_add_initial_power_ups` hook (host-only).
  - CHANGELOG: v0.2.5-dev (2026-04-28) — "Added: Starting Boons".

### Curse disable
- **What:** Host disables any of 14 CW curses, suppressing both gameplay effects and themed visuals.
- **Evidence:**
  - Implementation: hooks on `MutatorHandler._activate_mutator`, `DeusMechanism.get_current_node_curse`, plus node theme / curse field gates (`chaos_wastes_tweaker.lua:251-334`).
  - All hook target function names verified to exist in VT2 source by audit (2026-05-13).

### Altar distribution override
- **What:** Host sets custom counts of upgrade / melee-swap / ranged-swap / boon altars per CW run. `0 = vanilla random`.
- **Evidence:**
  - Implementation: `chaos_wastes_tweaker.lua:343-381` — `get_deus_weapon_chest_type` override.
  - CHANGELOG: v0.3.0-dev (2026-05-01) — "Changed: Altar count defaults are now 0 = vanilla random". Range 0-9.

### Weapon trait ban
- **What:** Host bans any of 31 real CW weapon traits from appearing on weapon upgrades.
- **Evidence:**
  - Implementation: `chaos_wastes_tweaker.lua:389-502` — `apply_weapon_trait_filter` / `restore_weapon_trait_filter` wrapping 3 vanilla call sites (`generate_weapon`, `generate_weapon_for_slot`, `apply_weapon_trait_upgrade`).
  - CHANGELOG: v0.3.4-dev (2026-05-01) — "Fixed: Banned Weapon Traits list" (replaced 20-entry list, 7 no-ops, with 31 verified-real traits).
  - Verification method: `dump_traits` console command (CHANGELOG v0.3.3-dev) enumerates `DeusWeapons[*].baked_trait_combinations`.

### Khaine's Fury (Reckless Swings) tweak
- **What:** Reduces self-damage from 3→1 per hit and lowers the active-threshold from 50%→25% health, letting the boon stay active longer. Tooltip updates dynamically when enabled.
- **Evidence:**
  - Implementation: `chaos_wastes_tweaker.lua:1027-1070` — `apply_reckless_swings_tweak` / `revert_reckless_swings_tweak`.
  - CHANGELOG: v0.2.5-dev (2026-04-28) added the tweak; v0.3.0-dev renamed the toggle to match in-game display name "Khaine's Fury".
  - **Caveat:** uses hard-coded array indices — see `AUDIT_FINDINGS.md` #1. Works on current vanilla game; future-fragile.

### Bomb-boon balance (4 toggles)
- **What:** Four host-configurable rebalances — (a) uniform cooldown override, (b) mutual exclusion in random pool, (c) Endless Bombs consumes Morgrim's, (d) Ranger Veteran cannot save Morgrim's on grenade throw.
- **Evidence:**
  - Implementation: `chaos_wastes_tweaker.lua` — `bomb_boon_cooldown` override on `DeusPowerUpTemplates.drop_item_on_ability_use.buff_template.buffs[1].cooldown_durations`; mutex filter in `generate_random_power_ups`; `apply_pockets_full_of_bombs_buff` hook; `ActionChargedProjectileUtility.fire_charged_projectile` hook.
  - CHANGELOG: v0.4.0-dev (2026-05-10) — "Added: Bomb-boon balance toggles", with per-toggle implementation detail.

### Campaign potions in CW
- **What:** Adds vanilla campaign potions (speed, strength, concentration) to the CW potion spawn pool.
- **Evidence:**
  - Implementation: `chaos_wastes_tweaker.lua` `populate_pickups` hook.
  - CHANGELOG: v0.3.0-dev (2026-05-01) — "Fixed: Campaign potions in CW now actually spawn". Fix: cloned entries with adjusted `spawn_weighting` to match the CW potion scale (group-sum normalization done by `pickups.lua` at boot).
  - v0.7.64 (2026-05-19): toggle promoted from per-peer to host-synced.
  - **Caveat:** `CODE_REVIEW.md` (same day) still flags as MED severity — see `AUDIT_FINDINGS.md` "Stale".

### Holly DLC missions spawn pickups
- **What:** Adventure-injected Holly missions (Magnus / Cemetery / Forest Ambush) spawn ammo / healing / grenades / potions / painting_scrap / level_events pickups.
- **Evidence:**
  - Implementation: `PickupSystem._can_spawn` hook expanding the allowed-types whitelist to include vanilla campaign categories on injected-adventure levels.
  - CHANGELOG: v0.7.64 (2026-05-19).

### Belakor locus gated to Belakor mission
- **What:** Belakor locus only spawns on the cursed mission, not on every injected-adventure level.
- **Evidence:**
  - Implementation: predicate now checks `current_node.curse == "curse_belakor_totems"`; new helper `_current_node_is_belakor()`.
  - CHANGELOG: v0.7.64 (2026-05-19).

### Manann's Tempest cooldown — unified toggle
- **What:** Single host-synced toggle `tweak_manann_tempest_cooldown` gates both the boon and the trait cooldown override. Default OFF.
- **Evidence:**
  - CHANGELOG: v0.7.64 (2026-05-19). Replaces the prior trait-only toggle; boon was previously hard-capped.

### Per-boon-scaling meta boons update on grant
- **What:** `ct_meta_health` / `_stagger` / `_crit` / `_cooldown` / `_ammo` / `_movespeed` recompute their stat scaling whenever any boon is gained, not only on the next mission load.
- **Evidence:**
  - Implementation: `on_boon_granted` handlers moved from `BuffFunctionTemplates.functions` to flat `ProcFunctions` — the engine only reads `on_boon_granted` from the latter.
  - CHANGELOG: v0.7.64 (2026-05-19).

### Host-synced run options
- **What:** `tweak_defeat_recovery` and `enable_campaign_potions` are now host-synced (host's value applies to all peers). `inject_adventure_maps` remains per-peer because injecting maps changes `LevelSettings` cardinality, which folds into the lobby combined-hash (`reference_vt2_lobby_combined_hash.md`).
- **Evidence:**
  - CHANGELOG: v0.7.64 (2026-05-19).

### Coin economy
- **What:** Host-configurable coin pickup multiplier and starting-coin grant.
- **Evidence:**
  - Implementation: `chaos_wastes_tweaker.lua:95-127` — `DeusRunController.on_soft_currency_picked_up` hook + `setup_run` injection.
  - **Caveat:** boon-count detection by value-range scan — see `AUDIT_FINDINGS.md` #3. Coin multiplier verified in CW runs.

### Run-config overrides
- **What:** Host-only force-Bel'akor's-Temple and finale-god overrides.
- **Evidence:**
  - Implementation: `chaos_wastes_tweaker.lua` `_setup_run` hook.
  - CHANGELOG: v0.3.0-dev family.

### Tooltip / localization cleanup
- **What:** 40 boon-disable / starting-boon widget tooltip refs that previously rendered as raw `<<key>>` were removed (the labels themselves were already auto-generated stubs).
- **Evidence:**
  - CHANGELOG: v0.3.2-dev (2026-05-01) — "Fixed: `<<key>>` placeholders in mod options menu".

---

## Features partially implemented / experimental

Wired in source but gated behind a flag or hidden in UI. **Not verified as functional end-to-end.**

- **`inject_adventure_maps` toggle** — fully implemented in `_adventure_pool.lua` (685 lines). Injects DLC campaign + event missions into the CW pool as `<key>_<theme>_path1` permutation entries with deus mechanism. Out of scope: arena nodes, shop nodes, finale arenas, Bel'akor's Temple, Citadel of Eternity. Default-off (`default_value = false`).
- **`any_trait_any_weapon` toggle** — setting exists in `_data.lua`; no UI widget; runtime check not yet hooked.

---

## Diagnostic commands

- `dump_traits` — dumps every weapon trait that can roll on any CW weapon, with `display_name` + `advanced_description` via `Localize()`. Added v0.3.3-dev. Data source for the Banned Weapon Traits list rewrite.
- `dump_adventure_names` — dumps `LevelSettings[<key>].display_name` for all adventure missions. Used to source display names for `inject_adventure_maps` catalog. Recorded 2026-05-13.
- `cw_status` (partial) — covers altar settings only per CODE_REVIEW.md; expansion deferred.

---

## Reference

- Companion: `AUDIT_FINDINGS.md` — assumption-class items NOT covered here.
- Audit method: AI-assisted with ground-truth verification against `Vermintide-2-Source-Code` decompiled source and cross-mod `CHANGELOG.md` files. Last full audit: 2026-05-13.
