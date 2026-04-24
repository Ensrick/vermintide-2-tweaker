# Chaos Wastes Tweaker — Feature To-Do

## Implemented
- [x] Coin pickup multiplier (slider 0.10x – 5.00x)
- [x] Set starting coin amount (0–3000)
- [x] Toggle individual curse modifiers on/off (14 curses, all CW curses covered)
- [x] Allow up to 5 boon options per shrine and per chest
- [x] Toggle friendly fire
- [x] Disable specific boons from appearing at shrines/chests/altars/Belakor's Temple (117 boon checkboxes)
- [x] Set starting boons (117 boon checkboxes; bypasses disabled-boons list; all players receive host's configured boons)
- [x] Configure altar type distribution (upgrade / melee swap / ranged swap / boon altars — 0–8 each; sum capped ~5–6 by map spawner slots)
- [x] Configure number of Chests of Trials per mission (slider 0–10)
- [x] Enable campaign potions (strength/speed/ability) in Chaos Wastes
- [x] Configure arena ammo box count (slider 0–10, default 2)
- [x] Any Trait on Any Weapon toggle
- [x] Banned weapon traits (27 trait checkboxes)
- [x] Boon/curse display names resolved from game localization at runtime (updates after first CW run in session)
- [x] `t unstuck` command — teleport to nearest living teammate
- [x] `t god` command — toggle invincibility
- [x] `t win` command — complete the current map
- [x] `t dump_boons` command — log boon IDs from next shrine/chest roll
- [x] Allow duplicate careers (host-only setting — multiple players can share the same hero/career)

- [ ] **Investigate Elf native weapon crash** — Native weapons like Glaive (`we_2h_axe`) and Dual Daggers (`we_dual_wield_daggers`) are causing engine assertion failures in `spawn_unit`. Added aggressive logging and runtime guards to help isolate the cause.
- [ ] **Verify Settings Sync** — Ensure `weapon_tweaker` settings are correctly applied on the client for non-host players.
- [ ] **Complete weapon_tweaker_data.lua** — Add the missing career weapon checkboxes to the new modular project.

---

## Economy & Starting Conditions
- [ ] **Loot rat drops: add Chest of Trials** — inject `deus_cursed_chest` into `LootRatPickups.deus` at startup and re-normalize weights. Drop spawns at rat's world position via `spawn_network_unit`, no pre-placed spawner needed. Make weight configurable (slider). Verify `AllPickups["deus_cursed_chest"]` exists and `can_spawn_func` passes in CW.

## Curses & Modifiers
- [ ] Change the number of modifiers on missions
- [ ] Adjust modifier bonus values (e.g. +5% movement speed → configurable %; add new bonus types like power vs. chaos)
- [ ] **Mutator selector** — choose which mutators can appear / force specific ones (see Shazbot's mutator mod for reference)
- [ ] **Make new Chaos Wastes curses from existing mutators** (e.g. expose campaign mutators as selectable curses)

## Boons
- [ ] **Reduce self-damage on "25% power vs chaos" boon** — boon deals 3 damage to self on each swing; change to 1. Requires finding the buff/mutator that drives the self-hit and overriding the damage value.
- [ ] Reduce spawn rarity of specific boons (per-boon percentage weight)
- [ ] Allow customizing how many boons per Chest of Trials
- [ ] Increase the pool/range of available boons (e.g. allow boons/talents normally excluded from Chaos Wastes)
- [ ] Allow blue and green tier weapons to have traits
- [ ] Per-boon career restrictions (data in `DeusPowerUpExclusionList` / `DeusPowerUpIncompatibilityPairs`)

## Miracles & Shrines
- [ ] Customize which miracles are available at shrines (including Miracle of Isha)
- [ ] Customize which types of shrines appear
- [ ] Change the Power Bonus miracle to transfer to a new weapon (and update its description text)
- [ ] Randomize miracles available at all shrines
- [ ] Adjust the number of enemies that spawn at chests

## Map & Structure
- [ ] Change the coin cost of using upgrade altars
- [ ] **Research: campaign maps in Chaos Wastes** — campaign/adventure maps don't have `primary_pickup_spawners` baked in for CW altars/chests. Would require adding each level to `DEUS_LEVEL_SETTINGS` with correct themes, paths, and locations. Likely requires custom level packages; investigate if any workaround exists.

## Weapons
- [ ] **GiveWeapon command** — give any weapon by item key (integrate from Shazbot/Vermintide-Mods) (Perhaps there's a way to use the in-game crafting menu in modded realm to allow the player to craft items just for modded)
- [ ] **AnyWeapon** — allow any weapon regardless of career restrictions (integrate from Shazbot/Vermintide-Mods)

## Multiplayer
- [ ] **Settings sync review** — decide which settings should be host-authoritative (curse disabling, boon filtering, altar counts, Belakor override, friendly fire, potions, ammo) and enforce them for clients that affect shared game state.

## Audio
- [ ] **Skip/disable character voiceovers** — option to silence or suppress specific character voices and voiceover lines during missions.

## Careers
- [x] Allow duplicate careers — multiple players can pick the same hero/career (host setting)
- [ ] Change the Power Bonus talent
- [ ] Adjust Temporary HP (THP) talents
- [ ] **Talent/ability transplant** — swap one career's full talent tree and career ability with another's (e.g. give Battle Wizard all of Grail Knight's talents and passive/active ability). Purely data-driven: patch the career's `talents` table and `career_ability_template` at game-state init. No model or animation changes — the character looks the same but plays like a different career.
- [ ] **Per-talent overrides** — replace individual talent slots across any career (e.g. swap one THP talent for a different character's talent)
