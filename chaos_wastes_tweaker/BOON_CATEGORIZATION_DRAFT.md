# Boon Categorization — Working Draft

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

Boons 17-22 + 24-28 placed. Note: ability_cooldown_reduction (#23) stays in Properties (mission-reward only).

---

## Reference: full boon catalog with display names

(Populated as we go to avoid pre-imposing a structure.)
