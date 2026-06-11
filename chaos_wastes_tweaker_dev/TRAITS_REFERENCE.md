# VT2 Weapon Traits Reference

All weapon traits available on melee and ranged weapons in vanilla VT2 and Chaos Wastes. Source: `weapon_traits.lua`, ct localization, and verified via in-game tooltips.

The "Campaign" column marks traits that roll on weapons in the standard adventure mode. "CW-only" traits are exclusive to Chaos Wastes weapon altars.

---

## Trait list

| # | In-game name | Internal ID | Campaign? | Description |
|---:|---|---|:---:|---|
| 1 | **Off Balance** | `melee_increase_damage_on_block` | yes | Blocking an attack increases the damage the attacker takes for a short time. |
| 2 | **Resourceful Combatant** | `melee_reduce_cooldown_on_crit` | yes | Melee critical hits reduce the cooldown of your Career Skill. Internal cooldown. |
| 3 | **Heroic Intervention** | `melee_shield_on_assist` | yes | Assisting an ally under attack restores 15 temporary health for both players. |
| 4 | **Parry** | `melee_timed_block_cost` | yes | Timed blocks reduce stamina cost. |
| 5 | **Resourceful Sharpshooter** | `ranged_reduce_cooldown_on_crit` | yes | Ranged critical hits reduce the cooldown of your Career Skill. Internal cooldown. |
| 6 | **Inspirational Shot** | `ranged_restore_stamina_headshot` | yes | Headshots restore stamina to nearby allies. |
| 7 | **Regrowth** | `melee_heal_on_crit` | no | Critical hits restore a small amount of health. |
| 8 | **Barrage** | `ranged_consecutive_hits_increase_power` | yes | Consecutive attacks against the same target boost attack power for a short time. |
| 9 | **Hunter** | `ranged_increase_power_level_vs_armour_crit` | yes | Critical hits increase attack power against targets of the same armour class for a short time. |
| 10 | **Thermal Equalizer** | `ranged_reduced_overcharge` | yes | Weapon generates less overheat. |
| 11 | **Heat Sink** | `ranged_remove_overcharge_on_crit` | yes | Critical hits refund the overcharge cost of the attack. |
| 12 | **Opportunist** | `melee_counter_push_power` | yes | Increases push strength when used against an attacking enemy. |
| 13 | **Swift Slaying** | `melee_attack_speed_on_crit` | yes | Critical hits increase attack speed for several seconds. |
| 14 | **Scrounger** | `ranged_replenish_ammo_on_crit` | yes | Critical hits replenish a small amount of ammunition. |
| 15 | **Conservative Shooter** | `ranged_replenish_ammo_headshot` | yes | Headshots have a chance to not consume ammunition. |
| 16 | **Bloodthirst** | `bloodthirst` | no | Increases Attack Speed for every few kills (stacks). Resets if you don't kill anything for a while. |
| 17 | **Vaul's Tempo** (Crescendo Strike) | `crescendo_strike` | no | Every Critical Hit increases your Crit chance for a short time. Stacks. |
| 18 | **Follow Up** | `follow_up` | no | Melee headshots grant your next attack a Critical Hit. Internal cooldown. |
| 19 | **Deadeye** (Headhunter) | `headhunter` | no | Each headshot increases the damage of the next attack (stacks). Hitting anywhere other than the head removes a stack. |
| 20 | **Shard Strike** (Armor Breaker) | `armor_breaker` | no | Killing an armoured enemy sends metal shards to damage other nearby enemies. |
| 21 | **Myrmidia's Leveller** (Big Swing Stagger) | `deus_big_swing_stagger` | no | Striking multiple enemies in one swing increases stagger power for several seconds. |
| 22 | **Asuryan's Wrath** (Collateral on Melee Kill) | `deus_collateral_damage_on_melee_killing_blow` | no | Melee attacks that kill enemies have a chance to deal damage to an additional nearby enemy. |
| 23 | **Manann's Tempest** (Crit Chain Lightning) | `deus_crit_chain_lightning` | no | Critical strikes trigger a chain lightning that jumps to nearby enemies. |
| 24 | **Huanchi's Fangs** (Serrated Blade) | `serrated_blade` | no | Melee attacks cause Bleed. |
| 25 | **Quetzl's Repulsion** (Home Run) | `home_run` | no | Increases knockback from staggering attacks and pushes. |
| 26 | **Anath Raema's Swiftness** (Ammo Pickup Reload) | `deus_ammo_pickup_reload_speed` | no | Picking up ammunition grants decreased reload time for several seconds. |
| 27 | **Taal's Twinned Arrow** (Extra Shot) | `deus_extra_shot` | no | Ranged attacks now fire one additional projectile. |
| 28 | **Addaioth's Splendour** (Ranged Crit Explosion) | `deus_ranged_crit_explosion` | no | On a cooldown, ranged Critical Hits explode in an area around the target. |
| 29 | **Asaph's Endless Quiver** (Refilling Shot) | `refilling_shot` | no | Ranged Critical Hits cost no ammunition. |
| 30 | **Anatha Raema's Talons** (Piercing Projectiles) | `piercing_projectiles` | no | Increase ranged attack penetration. |
| 31 | **Vaul's Anvil** (Always Blocking) | `always_blocking` | no | While wielding your melee weapon, all attacks made against you count as being blocked. When your block is broken you lose this effect briefly. |
| 32 | **Divine Shield** (Shield of Isha) | `shield_of_isha` | no | Damage taken is reduced to a minimum value or half of its original, whichever is higher. |
| 33 | **Rhya's Thorns** (Shield Splinters) | `shield_splinters` | no | Breaking shields sends splinters at the nearest enemies dealing damage. |
| 34 | **Shockwave** | `stagger_aoe_on_crit` | no | Critical hits stagger nearby enemies. |

---

## Tier assignment (user-driven, in progress)

### Tier 1 — Common/Green (confirmed 7)
- Off Balance
- Resourceful Combatant
- Heroic Intervention
- Parry
- Resourceful Sharpshooter
- Inspirational Shot
- **Rhya's Thorns** (shield break → splinters + small stagger to nearby; conditional on shield enemies)
- **Anath Raema's Swiftness** (ammo pickup → -50% reload for 10s)
- **Myrmidia's Great Leveller** (hit 5+ enemies in one swing → +50% stagger power, 3s)

### Tier 2 — Rare/Blue (confirmed 7)
- Regrowth
- Barrage
- Hunter
- Thermal Equalizer
- Heat Sink
- Opportunist
- **Bloodthirst** (+10% AS max @ 5 stacks, decays after 30s idle)
- **Scrounger** (ranged crit → small ammo refund) *(also T3.)*
- **Conservative Shooter** (headshot → chance to not consume ammo) *(also T3.)*
- **Deadeye** (Headhunter) (+10% dmg per headshot stack, max 20 = +200%; -1 stack on body shot — high ceiling but ramp is ridiculously hard)
- **Follow Up** — 3s ICD, melee headshot → guaranteed crit next attack. User: "T2, ~1 crit every 4-5 hits effectively."

### Tier 3 — Exotic/Orange (confirmed 3)
- **Divine Shield** (Shield of Isha) — damage = max(20, half of original); shield-only. User verdict: "between exotic and unique, I'll go exotic."
- **Shockwave** — every crit (NO cooldown) → AOE stagger to nearby enemies. Heavy melee + most ranged. User: "T3 for now, possibly T4 — stagger only but high uptime with CW crit builds."
- **Huanchi's Fangs** (Serrated Blade) — melee attacks cause bleed; fast-attack melee.
- **Addaioth's Splendour** — ranged crit → AOE explosion (10s ICD, 10% of hit damage, hero-power scaled, staggers). *(also T4 per later user revision.)*
- **Swift Slaying** — melee crit → +20% AS, 5s, refreshing.

### Tier 4 — Unique/Veteran (confirmed 2)
- **Shard Strike** (Armor Breaker) — Kill armoured → 16s damaging stagger aura. User verdict: "OP, top tier only." Plus: planned **Rework toggle to nerf duration** (vanilla 16s, configurable).
- **Anatha Raema's Talons** — +1 ranged penetration. *(also T3.)*
- **Asaph's Endless Quiver** (Refilling Shot) — ranged crits cost no ammo; firearms only.
- **Vaul's Tempo** (Crescendo Strike) — +5% crit per stack, max 10 = +50% crit chance, 10s per stack. *(also T3.)*
- **Quetzl's Repulsion** (Home Run) — +1000% ragdoll, +50% stagger knockback, +40% stagger power; Great Hammer only.
- **Asuryan's Wrath** — 50% chance on melee kill → killing-blow damage to nearby enemy; all melee weapons. *(also T3.)*
- **Manann's Tempest** — crit → chain lightning to 5 nearest enemies, ignores armour, no apparent cooldown.
- **Taal's Twinned Arrow** — +1 projectile per ranged shot, no extra ammo cost.
- **Vaul's Anvil** (Always Blocking) — passive block while melee wielded; block-break disables for 10s; shield-only.
- **Addaioth's Splendour** — ranged crit → AOE explosion (10s ICD, 10% damage, hero-power scaled). *(also T3.)*

### Tier 3 + Tier 4 (rolls on Exotic AND Unique) — additions
- **Vaul's Tempo** — see above.

### Tier 3 + Tier 4 (rolls on Exotic AND Unique)
- **Anatha Raema's Talons** — +1 ranged penetration. User: "extremely powerful on certain weapons, mediocre on others."

---

## Design notes from walk

**Model shift:** Traits don't need strict single-tier membership. Each trait declares a SET of rarities it can appear at (Common / Rare / Exotic / Unique). A trait like Talons may roll only at Exotic+Unique (skipping the lower rarities) because its impact varies by weapon. This is the "trait-roll eligibility per rarity" model.

**Planned sub-toggle: "Guaranteed Trait Reroll on Upgrade."** When the master trait-tier toggle is on, weapon upgrades reroll the trait every time — no chance of getting the same trait twice in a row. Eliminates wasted altar costs from duplicate rolls. User asked for this during Anatha Raema's Talons placement.

### Awaiting placement (22 traits)
- Swift Slaying
- Scrounger
- Conservative Shooter
- Bloodthirst
- Vaul's Tempo (Crescendo Strike)
- Follow Up
- Deadeye (Headhunter)
- Shard Strike (Armor Breaker)
- Myrmidia's Leveller
- Asuryan's Wrath
- Manann's Tempest
- Huanchi's Fangs (Serrated Blade)
- Quetzl's Repulsion (Home Run)
- Anath Raema's Swiftness
- Taal's Twinned Arrow
- Addaioth's Splendour
- Asaph's Endless Quiver (Refilling Shot)
- Anatha Raema's Talons (Piercing Projectiles)
- Vaul's Anvil (Always Blocking)
- Divine Shield (Shield of Isha)
- Rhya's Thorns (Shield Splinters)
- Shockwave

---

## Notes

- The Steam Community guide referenced (https://steamcommunity.com/sharedfiles/filedetails/?id=2458224546) confirmed that CW has exclusive trait sections ("Exclusive Weapon Trait — Original" and "Exclusive Weapon Trait — Be'lakor update") but the trait descriptions weren't in the fetched content.
- Vanilla `get_possible_trait_combinations` in `deus_weapon_generation.lua:166-169` ONLY rolls traits at exotic/unique rarity in CW. Tiering at lower rarities requires the rework toggle to also override that check.
- Trait combinations are baked PAIRS, not individual traits. Tier-filtering operates on combo level: a combo is allowed at rarity X if the highest-tiered trait in the combo is ≤ X (additive) or == X (strict).
