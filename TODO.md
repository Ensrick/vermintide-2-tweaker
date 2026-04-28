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
- [ ] **GiveWeapon command** — give any weapon by item key (integrate from Shazbot/Vermintide-Mods)
- [x] **AnyWeapon** — allow any weapon regardless of career restrictions (implemented in weapon_tweaker)
- [ ] **Modded-realm crafting** — hook the in-game crafting menu to allow crafting weapons only in modded realm, bypassing normal restrictions
- [ ] **Weapon illusion/cosmetic swapper** — change weapon illusions and cosmetics in modded realm only, using the existing crafting UI

## Multiplayer
- [ ] **Settings sync review** — decide which settings should be host-authoritative (curse disabling, boon filtering, altar counts, Belakor override, friendly fire, potions, ammo) and enforce them for clients that affect shared game state.

## Cosmetics
- [ ] **Cosmetic unlocks** — enable cosmetics (hats, skins) across careers within the same character (no cross-character; skip wh_priest), like weapon_tweaker unlocks weapons by patching `can_wield`/item filters. **In progress in `cosmetics_tweaker` mod (Workshop 3715714222, private).** Started v0.2.0 with `cos probe_cosmetics` runtime probe to enumerate items + native career allow-lists; next pass populates static unlock maps and the nested settings UI.
- [ ] **Per-hat character portraits (future)** — when the cosmetic-unlocks UI is in, layer a portrait-override system on top: for every hat a character can wear, generate a matching character portrait via Photoshop + AI character-consistency tools so the lobby/HUD portrait swaps to match the equipped hat. Static asset pipeline (one portrait per hat × character), runtime side just patches the active portrait based on equipped hat.
- [ ] **Cross-character hat unlocks (investigation)** — figure out which hat→character combos are skeleton-compatible. Currently `cosmetics_tweaker` is intra-character only because cross-character would crash on skeleton-attachment-node mismatch (e.g. Kruber wearing Kerillian's hat). Some pairs may share enough headpiece rigging to work — needs per-pair empirical testing.
- [ ] **Cloned + recolored cosmetics ("matching hats")** — generate new hat (and sometimes outfit) variants by cloning an existing item and tinting its materials to match a specific outfit's palette, where vanilla provides no matching combo. Concrete example: Grail Knight's white purified Chaos Wastes outfit has no white hat to pair with; clone a GK hat and tint it white. Two-part task:
  1. **Item cloning** — register a new entry in `ItemMasterList` at boot that copies an existing item's `unit`, `slot_type`, `can_wield`, etc., with a new unique key/display_name. Verify it shows up in inventory and equips.
  2. **Per-clone color override** — apply tint via `Material.set_color`/`set_vector3` on the spawned unit, only for the cloned variant (so the original hat stays vanilla). Use `Material.get_color` (or equivalent getter) to sample the target outfit's color so the recolor automatically matches; alternatively expose RGB sliders per clone.
  Requires confirming Stingray exposes BOTH getters and setters on material parameters, and that we can spawn a per-unit material instance so tinting one player's hat doesn't tint everyone else's.
- [ ] **Free weapon illusion/skin swap from inventory** — let the inventory menu pick any illusion/skin available to the weapon type without going through Okri's "apply illusion" flow (and without consuming a one-time illusion). Show all illusions for that weapon as selectable options inline on the weapon card.
- [ ] **3rd person mod** — enable 3rd person camera view so players can see their character model and cosmetics in gameplay

## Audio
- [ ] **Skip/disable character voiceovers** — option to silence or suppress specific character voices and voiceover lines during missions.

## Enemies & Bosses (General Tweaker)
- [ ] **Chief Krench from VT1** — port Chief Krench boss from Vermintide 1 into VT2 via modding (pending Fatshark permission — not just community manager approval)
- [ ] **Lords as monster spawns** — allow a selection of lord/boss enemies to spawn in place of regular monsters (e.g. Bodvarr, Skarrik, Rasknitt, Nurgloth as random monster replacements)

## Careers
- [x] Allow duplicate careers — multiple players can pick the same hero/career (host setting)
- [ ] Change the Power Bonus talent
- [ ] Adjust Temporary HP (THP) talents
- [ ] **Talent/ability transplant** — swap one career's full talent tree and career ability with another's (e.g. give Battle Wizard all of Grail Knight's talents and passive/active ability). Purely data-driven: patch the career's `talents` table and `career_ability_template` at game-state init. No model or animation changes — the character looks the same but plays like a different career.
- [ ] **Per-talent overrides** — replace individual talent slots across any career (e.g. swap one THP talent for a different character's talent)
