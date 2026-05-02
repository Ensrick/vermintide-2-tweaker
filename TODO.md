<!--
REVIEW (2026-05-01):
- File title says "Chaos Wastes Tweaker" but content covers MULTIPLE mods (chaos_wastes_tweaker,
  weapon_tweaker, career_tweaker, enemy_tweaker, cosmetics_tweaker). Title is misleading.
  Recommend renaming to "Tweaker Project — Master Feature To-Do" or splitting per-mod sections
  more explicitly (most per-mod TODOs already live in <mod>/TODO.md anyway).
- "Implemented" section lists `t unstuck`, `t god`, `t win`, `t dump_boons` with the LEGACY
  prefix `t`. These commands are now in chaos_wastes_tweaker under the `ct` prefix
  (or general_tweaker / weapon_tweaker as applicable). Update prefixes to match current bindings.
- "Investigate CW ghost scythe 3P spawn crash" entry references CROSS_CAREER_PACKAGE_FIX.md as
  "partially obsolete — original cross-career theory was wrong" — that doc should get its banner
  updated to match (see review marker in that file).
- "Character Weapon Variants mod" entry says "Workshop 3716869446" — consistent with itemV2.cfg.
  But CLAUDE.md and DEVELOPMENT.md say "(unpublished)". CLAUDE.md and DEVELOPMENT.md are wrong.
- The "Audio" / "Skip/disable character voiceovers" entry — confirm whether this is in scope for
  general_tweaker or a new mod; unclear ownership.
-->
# Chaos Wastes Tweaker — Feature To-Do

## Implemented
- [x] Coin pickup multiplier (slider 0.10x – 5.00x)
- [x] Set starting coin amount (0–3000)
- [x] Toggle individual curse modifiers on/off (14 curses, all CW curses covered)
- [x] Allow up to 5 boon options per shrine and per chest
- [x] Toggle friendly fire
- [x] Disable specific boons from appearing at shrines/chests/altars/Belakor's Temple (all 172 boons, organized in 6 sub-groups)
- [x] Set starting boons (all 172 boons, 6 sub-groups; bypasses disabled-boons list; all players receive host's configured boons)
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

- [ ] **Investigate CW ghost scythe 3P spawn crash** — `spawn_unit` assertion on unit hash `877616b4d5c71f36` = `wpn_bw_ghost_scythe_01_3p` (base/Necromancer 3P model). Crash occurs during CW level transitions with an Unchained bot wielding the Ensorcelled Reaper (crashify://77917479-d053-4d34-b6b9-629878a7e6ec, crashify://e4062589-...). Unchained should resolve to `_fire_3p` via `right_hand_unit_override`, so the base variant being requested implies `career_name` was nil at spawn time. Reproduces WITHOUT cross-career weapons enabled. All vanilla code paths pass career_name correctly; suspected timing issue where bot `SimpleInventoryExtension._career_name` is nil during CW unit recreation. **Mitigated** in v0.10.14 with pcall guard + diagnostic logging in `create_equipment` hook — next crash will log weapon key, career_name, and override state to identify the exact failure. Vanilla bug also found: `deus_chest_preload_extension.lua:106-107` calls `get_weapon_packages` without `career_name` for upgrade altar preloads (benign — preload path only). See `CROSS_CAREER_PACKAGE_FIX.md` for earlier analysis (partially obsolete — original cross-career theory was wrong).
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
- [x] **Modified Boons: Reckless Swings tweak** — reduces self-damage from 3→1, lowers health threshold from 50%→25%, tooltip updates dynamically
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
- [x] **Modded-realm crafting** — Athanor forge repurposed as Mod Weapon Crafting UI (B hotkey). Shows all career weapons, creates items client-side via `backend_mirror:add_item()`. Property/trait editing via weave bubble grid. Session-only items (lost on restart). TODO: persistence, max rarity crafting
- [ ] **Weapon illusion/cosmetic swapper** — change weapon illusions and cosmetics in modded realm only, using the existing crafting UI
- [x] **Character Weapon Variants mod** — new standalone mod (`character_weapon_variants`, Workshop 3716869446) for cross-character weapon combinations. See `character_weapon_variants/TODO.md` and `CROSS_MOD_ARCHITECTURE.md` for details.

## Multiplayer
- [ ] **Settings sync review** — decide which settings should be host-authoritative (curse disabling, boon filtering, altar counts, Belakor override, friendly fire, potions, ammo) and enforce them for clients that affect shared game state.

## Audio
- [ ] **Skip/disable character voiceovers** — option to silence or suppress specific character voices and voiceover lines during missions.

## Enemies & Bosses (General Tweaker)
- [ ] **Chief Krench from VT1** — port Chief Krench boss from Vermintide 1 into VT2 via modding (pending Fatshark permission — not just community manager approval)
- [ ] **Lords as monster spawns** — allow a selection of lord/boss enemies to spawn in place of regular monsters (e.g. Bodvarr, Skarrik, Rasknitt, Nurgloth as random monster replacements)

## Enemy Tweaker (New Mod)
- [ ] **Horde composition overrides** — replace the breed mix in hordes via `HordeCompositionsPacing` table patching. Settings UI lets the player pick which enemy types appear in hordes (e.g. all Chaos Warriors, mixed Skaven+Chaos, Beastmen-only on Helmgart maps). Hook `compose_horde_spawn_list()` or patch composition tables at mod load.
- [ ] **Breed substitution** — global breed-swap map (e.g. every `skaven_slave` → `skaven_storm_vermin`). Hook `HordeSpawner.spawn_unit()` where `Breeds[breed_name]` is resolved, or intercept `ConflictDirector.spawn_queued_unit()` to replace the breed before queuing.
- [ ] **Custom horde presets** — predefined "fun" compositions players can toggle: "All Elites", "Beastmen Invasion" (Beastmen on non-Beastmen maps), "Chaos Patrol Hordes", "Mixed Faction Hordes" (Skaven + Chaos + Beastmen together). Each preset patches `HordeCompositionsPacing` entries with custom breed lists and weights.
- [ ] **Horde size multiplier** — slider to scale total enemy count per horde (0.5x–3.0x). Multiply the `{min, max}` range in each composition variant's breed entries.
- [ ] **Special/elite spawn rate** — adjust how frequently specials and elites appear in ambient spawns. Hook `ConflictDirector` pacing or modify `breed_packs` weights.
- [ ] **Boss/monster frequency** — slider to change how often monsters spawn during a level. Modify terror event intervals or monster pacing settings.
- [ ] **Per-faction toggle** — enable/disable entire factions (Skaven, Chaos, Beastmen) from spawning, or force a single faction for all spawns on any map.
- [ ] **Difficulty-independent breed stats** — override individual breed fields (`run_speed`, `health`, `threat_value`, `stagger_resist`) regardless of difficulty setting, using `Breeds[name]` table patching at mod load.

## Careers
- [x] Allow duplicate careers — multiple players can pick the same hero/career (host setting)
- [ ] Change the Power Bonus talent
- [ ] Adjust Temporary HP (THP) talents
- [ ] **Talent/ability transplant** — swap one career's full talent tree and career ability with another's (e.g. give Battle Wizard all of Grail Knight's talents and passive/active ability). Purely data-driven: patch the career's `talents` table and `career_ability_template` at game-state init. No model or animation changes — the character looks the same but plays like a different career.
- [ ] **Per-talent overrides** — replace individual talent slots across any career (e.g. swap one THP talent for a different character's talent)

## Cosmetics
- [ ] **Remove dirt/stains from outfits (shader toggle)** — the outfit shader has built-in `dirt_threshold` and `dirt_variation` scalar variables on `mtr_outfit` (and `mtr_skin`/`mtr_body`). Found in `unit_variation_settings.lua` — enemies use these for randomized weathering (e.g. chaos_fanatic: `dirt_threshold` range 80–100 scaled ×0.01 = 0.8–1.0, `dirt_variation` range 0–3). Player outfits use the same `mtr_outfit` material/shader (`cosmetic_utils.lua:6`), so the variable should be present.
  - **Simplest approach (try first):** After the player's outfit unit spawns, iterate meshes for `mtr_outfit`, and call `Material.set_scalar(material, "dirt_threshold", 1.0)` to push the threshold above all dirt mask values. This should hide all dirt with zero asset work — pure Lua, no dependencies. Also set on `mtr_skin`/`mtr_body` if those exist on the unit.
  - **Hook point:** `PlayerUnitCosmeticExtension.init` (after `change_skin_materials` / `change_skin_material_settings` apply), or `GearUtils.create_equipment`, or `CosmeticUtils.color_tint_unit` — whichever fires after the mesh unit is fully set up.
  - **Settings UI:** Toggle per-character or global "Clean outfit" checkbox. Could also expose a `dirt_threshold` slider (0.0 = maximum dirt, 1.0 = spotless) for fine control.
  - **Validation needed:** Confirm the shader variable exists on player outfit materials at runtime. If `Material.set_scalar` silently fails (no error but no effect), the variable may not be compiled into the player material variant. In that case, fall back to texture replacement via Material-Hijack (see below).
  - **Fallback (if shader toggle doesn't work):** Extract vanilla diffuse textures via `vt2_bundle_unpacker`, edit out dirt in Photoshop, package as new textures, swap via Material-Hijack `Material.set_texture()`. Same pipeline as "Cloned + recolored cosmetics" item. Dependencies: Material-Hijack, MoreItemsLibrary.
  - **Loremaster's Armoury does NOT do this.** Repo cloned to `c:\Users\danjo\source\repos\Loremasters-Armoury` ([GitHub](https://github.com/dalokraff/Loremasters-Armoury)). It has "Clean" shield variants (custom heraldry shields without battle damage) but does not touch character body outfit textures.
  - **Reference:** `unit_variation_settings.lua:293-312` (dirt_threshold/dirt_variation definitions), `cosmetic_utils.lua:5-26` (color_tint_unit targets mtr_outfit), `player_unit_cosmetic_extension.lua:75-94` (skin init flow with material_changes → material_settings → color_tint).
