# Chaos Wastes Tweaker — Playtest Feedback

Running log of items collected during play. Append freely; I'll categorize, scope, and sequence into changelog entries / TODOs.

Format: each item gets a short title, a status tag, and notes. Statuses:
- **bug** — something works wrong vs intended
- **feature** — new capability requested
- **tune** — value/balance adjustment
- **research** — needs vanilla investigation before scope is clear

When you give me details for an item, I'll either fill out the design here, or pull it into a CHANGELOG entry + ship.

---

## Bugs

### Curses and boon rewards not syncing to host
- **Status:** bug
- **Logged:** 2026-05-14, multiplayer playtest with friend
- **Symptom (from user):** TBD — need specifics. Which curses? Which boon-reward channels (chest of trials? per-altar boons? finale rewards?) Which player observes the desync (host or client)?
- **Open questions for next session:**
  1. Reproduces with a vanilla CW run (no override settings), or only with mod-overridden curses / counts?
  2. Host sees X, client sees Y — what's the actual divergence?
  3. Network-relevant log lines from both peers (look for `[SharedState] deus_run_state_*` updates).

---

## Features

### Boon idea: 1 green HP per kill
- **Status:** feature (boon design)
- **Logged:** 2026-05-14
- **Pitch:** new boon that grants +1 green health on every enemy kill. Similar to vanilla life-leech patterns but tied to kill events instead of damage dealt.
- **Open questions:**
  1. Per-kill amount fixed at 1, or scale by enemy tier (1 trash / 3 elite / 10 special / 50 boss)?
  2. Counts assisted kills, last-hit only, or any-damage-credit?
  3. Cap at max health, or overheal into temp HP?
  4. Per-player or shared (host-applied)?
  5. Rarity tier (common / rare / unique)?
  6. Suggested god affinity (probably nurgle — corruption / life themes — or maybe khorne for kill-trigger).

### New curses from existing boons and modifiers
- **Status:** feature
- **Logged:** 2026-05-14
- **Pitch:** there are vanilla boons and mutator-style modifiers that would make compelling "curses" if their effects were applied to the run instead of granted to the player. Build new curse mutators using those effects.
- **Open questions for next session:**
  1. Concrete list — which boons / modifiers do you want to convert?
  2. Per curse: god assignment (khorne / nurgle / tzeentch / slaanesh / belakor), intensity scaling, opt-in or always-on, themed name / loc strings.
  3. Should these be on by default or behind a "modded curse pool" toggle?

### Boon menu sort + categorize — proposed Category 1 & 2

**Category 1: Healing / THP / Health Gain** (alphabetical by display name)

| Display name | setting_id |
|---|---|
| Bomb of Alchemical Rejuvenation | `boon_supportbomb_healing_01` |
| Coin Pickup Regen | `deus_coin_pickup_regen` |
| Curative Empowerment | `curative_empowerment` |
| Hand of Shallya | `hand_of_shallya` |
| Healer's Touch | `healers_touch` |
| Health | `health` |
| Health Orbs | `health_orbs` |
| Health Regeneration | `deus_health_regeneration` |
| Increased Healing Taken | `deus_increased_healing_taken` |
| Invigorating Strike | `invigorating_strike` |
| Last Player Standing Power Regen | `last_player_standing_power_reg` *(borderline — also gives power)* |
| Max Health | `deus_max_health` |
| Natural Bond | `natural_bond` |
| Pickup Heal | `deus_ammo_pickup_heal` |
| Power Up of Shallya | `power_up_of_shallya` |
| Regen on Dealt DoT Damage | `heal_on_dot_damage_dealt` |
| Resolve | `resolve` |
| Revive Regen | `deus_revive_regen` |
| Righteous Regeneration | `boon_skulls_04` *(borderline — currently in Skulls set group)* |
| Tenacious | `tenacious` |
| Transfer Temp Health at Full | `transfer_temp_health_at_full` |

**Category 2: Defense / Damage Reduction / Parry** (alphabetical by display name)

| Display name | setting_id |
|---|---|
| Barkskin | `barkskin` |
| Block Cost Reduction | `block_cost` |
| Block Procs Parry | `deus_block_procs_parry` |
| Damage Reduction on Incapacitated | `deus_damage_reduction_on_incapacitated` |
| Explosive Pushes on Damage Taken | `explosive_pushes_on_damage_taken` |
| Hidden Escape | `hidden_escape` *(borderline — invisibility, currently in Healing group)* |
| Knockdown Damage Immunity Aura | `deus_knockdown_damage_immunity_aura` |
| Missing Health Power Up | `missing_health_power_up` |
| Parry Damage Immune | `deus_parry_damage_immune` |
| Pent-Up Anger | `pent_up_anger` *(borderline — block-stack triggers crit attack)* |
| Protection Aoe | `protection_aoe` |
| Protection Chaos | `protection_chaos` |
| Protection Orbs | `protection_orbs` |
| Protection Skaven | `protection_skaven` |
| Push Block Arc | `push_block_arc` *(push-related, borderline)* |
| Push Charge | `deus_push_charge` *(push-related, borderline)* |
| Push Cost Reduction | `deus_push_cost_reduction` |
| Push Increased Cleave | `deus_push_increased_cleave` *(push-related, borderline)* |
| Second Wind | `deus_second_wind` *(borderline — low-HP escape, currently in Healing)* |
| Skill by Block | `skill_by_block` |
| Speed Over Stamina | `speed_over_stamina` |
| Stamina | `stamina` |
| Standing Still Damage Reduction | `deus_standing_still_damage_reduction` |
| Static Blade | `static_blade` *(parry-triggered, borderline)* |
| Thorn Skin | `thorn_skin` |
| Timed Block Free Shot | `deus_timed_block_free_shot` |
| Uninterruptable Attacks | `deus_uninterruptable_attacks` *(borderline — survival via no-stagger)* |

**Borderline calls I want your verdict on before I shuffle the data file:**

1. **Push boons** (`push_block_arc`, `deus_push_charge`, `deus_push_increased_cleave`) — defensive or offensive? They use stamina/block but enable offense.
2. **Hidden Escape** — invisibility on crit. Defense or utility?
3. **Second Wind** — fall-below-X% triggers speed + brief invuln. Healing/sustain or defense?
4. **Last Player Standing Power Regen** — power + regen when all allies down. Healing or combat?
5. **Static Blade** — parry triggers lightning. Defense or combat?
6. **Righteous Regeneration** — currently in the "Skulls" set group with other Skulls boons; move out, or keep with its set?

Tell me yes/no on each borderline (or "your call" for the ones you don't care about), and any pulls/pushes I missed, then I'll do the data-file restructure in one pass.

### Boon menu sort + categorize
- **Status:** feature
- **Logged:** 2026-05-14
- **Pitch:** the `disable_boon_*` / `starting_boon_*` lists currently dump all ~172 boons in one flat alphabetical list. Group them by category (movement / damage / defense / ability / utility / etc.) so users can find related boons together and the menu is browsable.
- **Open questions for next session:**
  1. We go boon-by-boon — you tag each with a category (or batches of similar ones), I generate the new grouping.
  2. Display style: nested groups (collapsible)? Prefixed names ("[Damage] Strength Potion grants speed")? Or just clustered alphabetically within categories?

---

## Tunes

*(none yet — add here as they come up)*

---

## Research

*(none yet — add here as they come up)*

---

## Session notes
*(freeform — append observations in whatever shape; I'll restructure)*

### 2026-05-14
- **Fixed (v0.7.20):** client crash `deus_shop_view_v2.lua:182: attempt to index field '_shop_config' (a nil value)` when peers had mismatched `replace_shrines_with_missions` settings. Root cause: CW graph generation is deterministic from seed and runs on both host AND client. Our hook fired on both peers with their own settings, producing divergent local graphs. Host loaded the real shop level, client's local node had a different (TRAVEL-converted) level, shop_view UI nil-deref'd. Gated the entire `deus_populate_graph` hook on `is_server` so only host mutates. Clients pass through vanilla. Same fix prevents future similar bugs from any graph-modifying override.

- **Pending bug (already in queue):** curses + boon rewards not syncing to host. Specifics still needed — which curses, which reward channel, who observes the divergence. Possibly related to the same "two-peer-determinism with different settings" class of bug.

### 2026-05-19
- **Fixed (v0.7.64):** Holly DLC missions (Magnus / Cemetery / Forest Ambush) injected into the CW pool now spawn pickups correctly. Root cause: `PickupSystem._can_spawn` whitelisted only deus pickup types; vanilla campaign categories (ammo / healing / grenades / potions / painting_scrap / level_events) silently dropped on injected-adventure levels. Now allowed on those levels.
- **Fixed (v0.7.64):** Belakor locus only spawns on the actual Belakor cursed mission. Predicate now checks `current_node.curse == "curse_belakor_totems"` via new helper `_current_node_is_belakor()`.
- **Changed (v0.7.64):** Manann's Tempest cooldown is now a SINGLE toggle (`tweak_manann_tempest_cooldown`) that gates BOTH the boon and the trait. Default OFF. Previously only the trait was toggleable; the boon was hard-capped.
- **Fixed (v0.7.64):** Per-boon-scaling meta boons (`ct_meta_health` / `_stagger` / `_crit` / `_cooldown` / `_ammo` / `_movespeed`) now update on every boon gain instead of only on the next mission load. Root cause: granted-proc handlers were registered in `BuffFunctionTemplates.functions`, but the engine reads `on_boon_granted` from the flat `ProcFunctions` table.
- **Changed (v0.7.64):** `tweak_defeat_recovery` and `enable_campaign_potions` are now host-synced settings (was per-peer). `inject_adventure_maps` remains per-peer due to the lobby combined-hash constraint (see `reference_vt2_lobby_combined_hash.md`).
