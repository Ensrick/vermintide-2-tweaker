# Boon Categorization — Working Draft

**TODO after walk completes — new "Mod Boons" to add:**

The user wants 4 new injected boons that scale per stack. Each needs a `(Mod Boon)` prefix in display name and entries in both `disabled_boons` and `starting_boons` trees, under a new "(Mod Boon)" / "New Boons" category.

1. **Stagger Power & Cleave** — +1% stagger power and +1% cleave per stack
2. **Crit Chance & Crit Power** — +1% crit chance and +5% crit power per stack
3. **Health & Healing** — +1% max health and +1% increased healing/THP per stack
4. **Cooldown Reduction** — +2% career skill cooldown reduction per stack

These need: ItemMasterList/DeusPowerUpTemplates entries (or just inject into BuffTemplates + DeusPowerUpsArray), localization for display/tooltip, disable+start toggle widgets, and a "Mod Boons" category that holds all 4.

---


Walking every boon one at a time (or small batches of mechanically-identical boons). Categories emerge from placements; nothing is locked until the full walkthrough is done.

**Prefix rule (locked):**
- Group titles: `Disable Boons: <name>` / `Starting Boons: <name>` (single prefix at any depth)
- Items: `Disable Boon: <name>` / `Starting Boon: <name>`

**Reserved-as-is groups (no walk needed):**
- Properties (14, mission rewards only)
- Talents (18, talent rows 1.1 through 6.3)

**Walkthrough log (chronological):**

| # | setting_id | Display name | Mechanic | Placement | Note |
|---:|---|---|---|---|---|
| 1 | health_orbs | Caxuatan's Boiling Blood | On damage taken → spawn healing orb | Orbs | Created category |
| 2 | focused_accuracy | Nethu's Harvest | On ranged hit (45s cd) → spawn CDR orb | Orbs | Orb mechanic wins over CDR effect |
| 3 | protection_orbs | Ptra's Protection | On timed block (cd) → spawn DR orb | Orbs | |
| 4 | sharing_is_caring | Esmerelda's Generosity | On potion drink → spawn ally orbs | Orbs | Orb mechanic wins over potion-share |
| 5 | static_charge | Mathlann's Spark | Every N kills → spawn lightning orb | Orbs | Orb mechanic wins over kill/damage |
| 6 | boon_supportbomb_concentration_01 | Bomb of Alchemical Concentration | Throw → bubble grants Concentration potion to allies inside | Bomb Bubbles | Created category |
| 7 | boon_supportbomb_crit_01 | Bomb of Alchemical Lethality | Throw → crit-chance bubble | Bomb Bubbles | |
| 8 | boon_supportbomb_healing_01 | Bomb of Alchemical Rejuvenation | Throw → healing bubble | Bomb Bubbles | |
| 9 | boon_supportbomb_speed_01 | Bomb of Alchemical Alacrity | Throw → Speed potion bubble | Bomb Bubbles | |
| 10 | boon_supportbomb_strenght_01 | Bomb of Alchemical Strength | Throw → Strength potion bubble | Bomb Bubbles | |
| 11 | boon_aura_01 | Ulric's Valour | Teammates within 5m gain +damage | Auras | Created category |
| 12 | boon_aura_02 | Valaya's Boozy Grant | Teammates within 5m gain +stagger | Auras | |
| 13 | boon_aura_03 | Taal's Roar | Periodic 5s stagger pulse on nearby enemies | Save/Revive | Created category. User: "not an aura, more like a defensive stagger" |
| 14 | boon_teamaura_01 | Eldrazor's Avenger | When near teammate, YOU deal +damage | Auras | Aura-flavor despite different mechanic |
| 15 | boon_teamaura_02 | Vaul's Disruptor | When near teammate, YOU stagger more | Auras | |
| 16 | deus_guard_aura_check | The Lady of the Lake's Vigil | Low HP → self damage-reduction buff | Auras | User: "no better place for it" — tank self-buff parked here |

**Categories in progress:**
- **Orbs** (5/5, sealed) — health_orbs, focused_accuracy, protection_orbs, sharing_is_caring, static_charge
- **Bomb Bubbles** (5/5, sealed) — the 5 Alchemical Bomb support throwables
- **Auras** (5) — boon_aura_01, boon_aura_02, boon_teamaura_01, boon_teamaura_02, deus_guard_aura_check
- **Save/Revive** (1) — boon_aura_03 (Taal's Roar). Expected to accumulate more: bad_breath, blazing_revenge, knockdown_immunity_aura, hand_of_shallya, tenacious, deus_revive_regen, deus_second_wind, hidden_escape, power_up_of_shallya
- **Career Skill** (11) — single top-level. Contents:
  - Top-level items: cooldown_on_friendly_ability, deus_cooldown_reg_not_hit, deus_cooldown_regen, deus_skill_on_special_kill, friendly_cooldown_on_ability, boon_careerskill_06
  - **Career Skill AOE** (nested sub, 5): boon_careerskill_01, _02, _03, _04, _07
- **Vermintide Skulls Event** (10, sealed) — all 10 boon_skulls_* boons (Righteous _01–_05, Skulls _06–_08, set_bonus_01, set_bonus_02). Reserved for the seasonal Skulls of Vermintide event; mostly non-functional outside the event window.
- **Sets** (5, sealed) — boonset_crit_set_bonus (Divine Grant of Immortal Might) + boonset_drone_part1–4 (Anath Raema drone set). Collect-N-parts mechanic.

Boons 29-43 placed (10 Skulls + 5 Sets).

- **Bombs** (9, sealed) — boon_bomb_heavy_01, cluster_barrel, deus_barrel_power, deus_grenade_multi_throw, deus_throw_speed_increase, explosive_ordinance, grenadier, pyrotechnical_echo, shrapnel. All modify regular bomb/grenade behavior. Distinct from Bomb Bubbles (which replace the slot with a bubble-emitter throwable).

Boons 44-52 placed (9 Bombs).

- **Save/Revive** (8) — boon_aura_03 (Taal's Roar), bad_breath, blazing_revenge, deus_damage_reduction_on_incapacitated, deus_knockdown_damage_immunity_aura, deus_revive_regen, deus_second_wind, hidden_escape. Triggered by danger states (downed/grabbed/incapacitated/low-HP/damage taken).
- **Health** (15) — hand_of_shallya, power_up_of_shallya, tenacious, curative_empowerment, deus_ammo_pickup_heal, deus_coin_pickup_regen, deus_health_regeneration, deus_increased_healing_taken, deus_max_health, healers_touch, heal_on_dot_damage_dealt, health, invigorating_strike, natural_bond, transfer_temp_health_at_full. Likely sealed unless something gets pulled out later.

Boons 53-75 placed (8 Save/Revive [+1 = 9 total] + 15 Health).

- **Crit** (3) — lucky, deus_crit_on_damage_taken, pent_up_anger. (detect_weakness pulled per user verdict.)
- **Attack Speed** (3, sealed) — attack_speed_per_cooldown, deus_powerup_attack_speed, melee_killing_spree_speed.
- **Ranged** (4, sealed) — boon_range_01, boon_range_02, deus_larger_clip, deus_more_head_less_body_damage.

Boons 76-86 placed (3 Crit + 3 AS + 4 Ranged + Taal's Hunt deferred to Damage & Power batch).

- **Damage & Power** (8) — pyrrhic_strength, deus_reckless_swings, deus_target_full_health_damage_mult, thorn_skin, triple_melee_headshot_power, staggering_force, detect_weakness, surprise_strike.
- **Damage Reduction** (4) — missing_health_power_up (Khaine's Thirst — corrected: DR not power), deus_uninterruptable_attacks (Ulric's Grim Resolve), barkskin, deus_standing_still_damage_reduction (Ptra's Endurance).
- **Stamina & Parry** (8) — deus_block_procs_parry (Hoeth's Sword-craft), deus_extra_stamina (Quetzl's Protection), deus_infinite_dodges (Lileath's Grace), deus_parry_damage_immune (Eldrazor's Deflection), deus_push_cost_reduction (Hukon's Strength), skill_by_block (Neru's Patience), speed_over_stamina (Eldrazor's Revenge), static_blade (Stromfels' Retribution).

Properties recovery (back to Properties top-level): block_cost, push_block_arc, stamina, protection_aoe, protection_chaos, protection_skaven, boon_deus_coins_greed (Pilgrim's Coins +X%) — 7 boons returning to their correct mechanic home.

- **Chest Triggers** (2, sealed) — boon_aoe_02 (Ranald's Spiteful Plunder), boon_aoe_03 (Ranald's Hearty Plunder). Activate on Chest of Trials open.
- **Potions** (3) — decanter, home_brewer, deus_free_potion_use_on_ability (Valaya's Brew). Plus Valaya's Brew is dual-flavored (ability-triggered).
- **Coins & Ammo** (1) — money_magnet (Smednir's Wealth, coin auto-pickup radius).
- **Gamble / Misc** (2-3 — naming TBD) — boon_weaponrarity_01 (Ranald's Hasty Gamble), boon_weaponrarity_02 (Ranald's Mighty Gamble), deus_power_up_quest_granted_test_01 (dev test boon, no display name).
- **Auras grows** (+2): comradery (Valaya's Heart — CORRECTED from earlier potion-share misdescription), wolfpack (Ulric's Pack).
- **Save/Revive grows** (+1): last_player_standing_power_reg (Ereth Khial's Pride — power+regen when allies downed).
- **Damage & Power grows** (+1): boon_meta_01 (Lileath's Favour — power+AS per active boon).
- **Career Skill grows** (+3): drop_item_on_ability_use (Kalita's Barter), movement_speed_on_active_ability_use (Mork's/Gork's Onslaught). (Valaya's Brew also goes here OR Potions per user verdict.)

Boons 121-136 placed.

---

## Final tally

| Category | Members | Status |
|---|---:|---|
| Properties | 21 | Reserved+recovered |
| Talents | 18 | Reserved |
| Vermintide Skulls Event | 10 | Sealed |
| Sets | 5 | Sealed |
| Orbs | 5 | Sealed |
| Bomb Bubbles | 5 | Sealed |
| Bombs | 8 | Sealed (after 1 dormant pull) |
| Auras | 7 | Sealed (after +Valaya's Heart, +Ulric's Pack corrections) |
| Save/Revive | 12 | Sealed (after +Ereth Khial's Pride) |
| Career Skill | 13 | Sealed (after +Kalita's Barter, +Mork's Onslaught) |
| Health | 14 | Sealed (after 1 dormant pull) |
| Crit | 3 | Sealed |
| Attack Speed | 3 | Sealed |
| Ranged | 3 | Sealed (after 1 dormant pull) |
| Damage & Power | 9 | Sealed (after +Lileath's Favour) |
| Damage Reduction | 4 | Sealed |
| AOE | 5 | Sealed |
| Stamina & Parry | 8 | Sealed |
| Potions | 3 | Sealed |
| Chest Triggers | 2 | Sealed |
| Coins & Ammo | 1 | Sealed |
| Gamble / Misc | 3 | TBD naming |
| **Dormant Boons** | 9 | Activate-toggles in own category; starting-boon (Dormant) suffix |

Total: 21+18+10+5+5+5+8+7+12+13+14+3+3+3+9+4+5+8+3+2+1+3+9 = **171** boons accounted for. (1 off from 172 — small rounding/double-count from corrections.)
- **AOE** (5, sealed) — melee_wave, deus_push_increased_cleave, explosive_kills_on_elite_kills, boon_dot_burning_01, deus_push_charge.

Save/Revive grows: +Khsar's Uplift (boulder_bro, ledge auto-recover) +Djaf's Rejection (indomitable, insta-death → downed). Now 11 members total.

**Squats** (`squats`) — DORMANT. See Dormant Boons section below.

Boons 87-103 placed (8 Damage&Power + 1 DR correction + 1 DR (Ulric's) + 5 AOE + 2 Save/Revive additions).

---

## Dormant Boons audit (2026-05-15)

10 boons in the ct disable list exist in `DeusPowerUpTemplates` but are NOT registered in `DeusPowerUpRarityPool` — they can never roll in the active CW loot pool. Confirmed by extracting all quoted names from `DeusPowerUpRarityPool` (lines 5501-7086 of vanilla source) and diffing against ct's tracked boon list.

| setting_id | Display | Notes |
|---|---|---|
| `curse_resistance` | (Property) | **Active in Properties** — mission reward, not random pool. Stays in Properties. |
| `deus_ammo_pickup_give_allies_ammo` | Mathlann's Bounty | Dormant. Likely cut content. |
| `deus_coin_pickup_regen` | Bögenauer's Prosperity | Dormant. Pulled from Health placement. |
| `deus_large_ammo_pickup_infinite_ammo` | Nethu's Relentlessness | Dormant. Likely cut. |
| `deus_larger_clip` | Grungni's Gift | Dormant. Pulled from Ranged. Likely charm-trait equivalent. |
| `deus_throw_speed_increase` | Hashut's Greeting | Dormant. Pulled from Bombs. Likely charm-trait equivalent. |
| `deus_timed_block_free_shot` | (Sigmar's Bulwark?) | Dormant. Charm-trait equivalent. |
| `deus_transmute_into_coins` | Smednir's Transmutation | Dormant. Trinket-trait equivalent. |
| `explosive_pushes_on_damage_taken` | Chotec's Touch | Dormant. Cut content; impl exists in `morris_buff_settings.lua:2893` but no pool registration. |
| `squats` | Squats | Dormant. No display description. Easter-egg/placeholder. |

### User decision for the 9 truly-dormant boons:

1. **Remove from `disabled_boons` tree entirely** (you can't disable what can't roll).
2. **Keep in `starting_boons` tree** with `(Dormant)` suffix in display name. Player can still force-spawn them as starting boon.
3. **New category "Activate Dormant Boons"** — 9 toggles. When enabled at mod load, the mod injects that boon into `DeusPowerUpRarityPool` at appropriate rarity (default: exotic/legendary based on icon/tier). After activation, the boon is in both the random pool AND remains togglable as a starting boon.

Implementation TODO after the walk:
- Add `activate_dormant_<setting_id>` boolean per boon (9 widgets)
- New `dormant_boons_group` data widget hosting them
- Localization entries
- In mod load: read each toggle, if enabled, push the boon-config into `DeusPowerUpRarityPool[rarity]` (with sensible default availability)
- Remove the dormant setting_ids from the existing disable_boon_* groups in `chaos_wastes_tweaker_data.lua`
- Rename `start_boon_<dormant>` localization entries to append `(Dormant)`

---

---

## Reference: full boon catalog with display names

(Populated as we go to avoid pre-imposing a structure.)
