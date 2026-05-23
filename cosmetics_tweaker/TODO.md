# Cosmetics Tweaker — Feature To-Do

## Open investigation
- [x] **`unlock_all_frames` toggle — RESOLVED, verified in-game (user confirmed 2026-05-16).** Fix shipped v0.7.100-dev (re-targeted `_create_fake_inventory_items` + `get_unlocked_cosmetics` hooks from `PlayFabMirrorBase` to `PlayFabMirrorAdventure` per `feedback_vt2_class_hook_derived.md`). All open verification sub-bullets below are closed.

  ### What we KNOW
  Empirical, from v0.7.99 in-game diagnostic at 03:02:45 on 2026-05-05:
  - Toggle on, modded realm detected (gates pass).
  - `ItemMasterList` has **239 frames**, **0 DLC-locked** for this user.
  - `_unlocked_cosmetics` had **159 frame entries** (the user's actually-owned baseline).
  - `get_filtered_items("slot_type == frame")` returned 159 — matches `_unlocked_cosmetics` 1:1, so the UI filter chain is *not* dropping items.
  - VMF log confirms the v0.7.99 base-class hook **registered** at 02:41:12.686, before PlayFab login at 02:41:22. Despite registration, it **fired 0 times**.

  From source code:
  - `boot.lua:1647` instantiates `PlayFabMirrorAdventure` for client play (not the base).
  - `foundation/scripts/util/class.lua:51-57` defines inheritance by **copying** parent methods into the child table at class-definition time — there is no `__index` chain to the base. Runtime instance holds its OWN copy of `_create_fake_inventory_items` and `get_unlocked_cosmetics`.
  - These two facts together explain why the base-class hook never fired.

  ### Fix in v0.7.100
  - Re-targeted both hooks to `PlayFabMirrorAdventure`.
  - Pre-hook on `_create_fake_inventory_items` mutates the `fake_inventory_items` parameter to inject all frame keys before fake backend IDs are minted.
  - Companion safe hook on `get_unlocked_cosmetics` keeps the table in sync for later UI re-queries.
  - Memory entry: `feedback_vt2_class_hook_derived.md` — "hook the derived class, not the base" applies to all VT2 method hooks.
  - Diagnostic command `/frames_status` retained in source.

  ### What we INFER but have NOT verified
  - **The fix actually works.** Strongly implied by theory + the empirical hook-never-fired evidence, but no in-game retest yet on v0.7.100.
  - **All 239 frames will display** once injected. The 159↔159 match between `_unlocked_cosmetics` and `get_filtered_items` is reassuring (no current downstream filter rejects valid frames), but new fake entries could conceivably trip something we haven't seen.
  - **DLC handling is correct.** Only checked for this user (0 DLC-locked). Untested for someone without all cosmetic DLCs.

  ### What we DON'T know
  1. **Does v0.7.100 actually populate to 239?** Single biggest open question. Needs a full restart + `/frames_status` re-run to close.
  2. **Runtime toggling still requires restart.** The pre-hook only fires inside `inventory_request_cb` (one shot at PlayFab login). Toggling off→on mid-session won't add frames without a restart. CHANGELOG already notes this; v0.7.100 doesn't change it.
  3. **Other class-copy victims across the mod suite are not yet audited.** Grepped `vermintide-2-tweaker/` for `mod:hook("PlayFabMirror...` — only the two we just fixed. **Did NOT** sweep other inheritance hierarchies (`BackendInterface*`, `GearUtils`, UI window classes, weapon templates). Same generic class-system bug likely hides in at least one other hook somewhere. → **follow-up task below**.
  4. **Whether the safe hook on `get_unlocked_cosmetics` is doing anything useful** now that the pre-hook handles the load-time path. Probably defensive/redundant; harmless either way. Could be deleted on cleanup.
  5. **Whether 239 is the "right" target.** Some frames may be event-only or otherwise hidden from the player by intent; would surface only on visual inspection of the populated grid.

  ### Verification checklist (next session)
  1. User restarts VT2 with v0.7.100 loaded.
  2. With toggle ON, run `/frames_status` in chat.
  3. Expected: `inject hook fired ≥ 1 time(s); last added=80`, `_unlocked_cosmetics contains 239 frame entries`, `get_filtered_items returned 239 items`.
  4. Open Cosmetics Inventory → Frames tab; visually confirm population looks right (not corrupted, not duplicated, etc).
  5. If all green: close this item, mark resolved, optionally delete the safe `get_unlocked_cosmetics` hook on cleanup.

- [ ] **Sweep mod suite for other base-class hooks that may silently never fire.** (filed 2026-05-05, follow-up from `unlock_all_frames` root cause.) The `class.lua:51-57` parent-method-copy means any `mod:hook("BaseClass", ...)` where the runtime instance is a derived class is broken. Candidates to audit across `weapon_tweaker`, `chaos_wastes_tweaker`, `general_tweaker`, `cosmetics_tweaker`, `character_weapon_variants`, `enemy_tweaker`, `career_tweaker`:
  - `BackendInterfaceItemPlayfab` vs `BackendInterfaceItem` parent
  - `BackendInterfaceCraftingPlayfab` vs `BackendInterfaceCrafting`
  - Any UI window class with `*_console` or platform-specific subclass
  - `GearUtils`-adjacent class hierarchies
  Quick pattern: `Grep` for `mod:hook(\_safe)?\(\s*"[A-Z]\w+"` then for each match, search the source for `<ClassName> = class(<ClassName>, <Parent>)` and a separate `<DerivedName> = class(<DerivedName>, <ClassName>)` line. If found, the hook should target the derived class.

- [ ] **Per-material painter for Kerillian LA shields (post-alpha polish).** Kerillian custom-mesh shields have TWO `mat_slots` in vanilla LA (slot1=handle, slot2=shield). The current `Unit.set_texture_for_materials` painter writes uniformly across all materials on the unit, so we use slot2's textures and the handle face ends up showing the shield diffuse instead of the handle diffuse. Visually imperfect but doesn't crash; acceptable for v0.8.51-dev alpha. Real fix: per-mesh-material targeting via `Mesh.material` + `Material.set_texture` on per-unit instance materials (the `set_all_materials` swap should have made them per-instance, so this would no longer mutate the shared global material). Verify via a second probe before implementing.

- [ ] **Decode crash unit hash `9405eeb80a227a76` and re-enable LA Imperial Hero mesh swap.** Crashed `World.spawn_unit` consistently across v0.7.81–v0.7.85 when the user clicked an Imperial LA shield (e.g. `Kruber_empire_shield_hero1_Ostermark01`, `_Kotbs01`) on a Bret sword + shield in the customization menu. Workaround in v0.7.86: `_la_bridge._resolve_intended_unit` always returns `nil`, so LA textures paint onto the user's current shield mesh — Imperial LA UVs land on Bret GK shields imperfectly but it doesn't crash. **Diagnostic build (v0.7.92-dev)** added a `[SPAWN_TRACE]` hook on `World.spawn_unit` and re-enabled the mesh swap to capture the failing unit name in `Console.log`. **Next step:** ask user to repro on v0.7.92, share the last 10–20 `[SPAWN_TRACE]` lines around the crash. The actual unit name (decoded from the hash) will tell us whether to:
  - preload the resource_package that contains the failing unit (likely some weapons-bundle, NOT `wastes_common` as v0.7.85 assumed), or
  - filter affected LA variants out of the picker pool when their packages aren't engine-resident, or
  - swap to a different reliably-loaded shield mesh that's UV-compatible.
- [ ] Once the diagnostic data lands and the fix is in, **remove the `[SPAWN_TRACE]` hook and the `/spawn_trace_reset` command** from `cosmetics_tweaker.lua` (the diagnostic block is clearly marked `TEMP DIAGNOSTIC`).
- [ ] Notes from prior investigation (don't redo):
  - `Application.can_get("unit", path)` returned **true** for the failing unit but `World.spawn_unit` still asserted. So `can_get` checks resource registry availability, NOT spawn-readiness.
  - LA's bootstrap loads `resource_packages/levels/dlcs/morris/wastes_common` and four similar globals at LA mod init. The deus shield 3p variants don't appear to be reliably available in keep contexts — LA's normal flow assumes the user has a CW Bret weapon equipped (which loads them via the loadout chain).
  - `Managers.package:load("units/.../wpn_es_deus_shield_03", ...)` on a non-existent standalone package writes `self._packages[path]` anyway (Application.resource_package returns a handle regardless), so `has_loaded` lied. v0.7.85 switched the gate to `can_get("unit", ...)`, which fixed the phantom-load issue but not the underlying spawn failure.

## In Progress
- [ ] **Independent offhand illusion swap** — second row of illusion buttons on the weapon customization screen for independently swapping left-hand (shield/offhand) models. Currently working: UI renders, button icons show rarity glow, scenegraph guards prevent crashes. **Dual-wield coverage added in v0.8.51-dev** (dr_dual_axes, dr_dual_wield_hammers, ww_dual_daggers + we_dual_wield_daggers alias, ww_dual_swords, ww_sword_and_dagger, es_dual_wield_hammer_sword, wh_dual_hammer, wh_dual_wield_axe_falchion) via runtime `_build_offhand_options_from_skin_table` helper. Remaining: in-game smoke-test dual-wield picker (does it appear, does selection apply, does in-game render swap correctly), per-option rarity assignment refinement, offhand selection persistence across sessions, hover/tooltip polish.

## Cosmetic Unlocks
- [ ] **Cosmetic unlocks** — enable cosmetics (hats, skins) across careers within the same character (no cross-character; skip wh_priest), like weapon_tweaker unlocks weapons by patching `can_wield`/item filters. **In progress in `cosmetics_tweaker` mod (Workshop 3715714222, private).** Started v0.2.0 with `/probe_cosmetics` runtime probe to enumerate items + native career allow-lists; next pass populates static unlock maps and the nested settings UI.
- [x] **Per-hat character portraits** — shipped in `dynamic_cosmetic_portraits` (Workshop 3721036701, private). Split out of cosmetics_tweaker on 2026-05-06; see `dynamic_cosmetic_portraits/{CHANGELOG,DEVELOPMENT,TODO}.md`.
- [ ] **Cross-character hat unlocks (investigation)** — figure out which hat→character combos are skeleton-compatible. Currently `cosmetics_tweaker` is intra-character only because cross-character would crash on skeleton-attachment-node mismatch (e.g. Kruber wearing Kerillian's hat). Some pairs may share enough headpiece rigging to work — needs per-pair empirical testing.

## Recolored / Cleaned Cosmetics
- [ ] **Cloned + recolored cosmetics ("matching hats")** — generate new hat/outfit variants by cloning an existing item with recolored textures so no vanilla matching combo is missing (concrete example: white GK hat to pair with the Purified Chaos Wastes outfit). Investigated 2026-04-28; pure-Lua color tinting is **not feasible** (VT2 hat shaders expose zero standard color/tint variables — probed 30 candidate parameter names, none matched; `Material.num_parameters`/`parameter_name` enumerator APIs hard-crash this build). Real path uses two existing community mods + asset-authoring work:
  - **Dependencies:**
    - [Material-Hijack](https://github.com/dalokraff/Material-Hijack) — hooks `GearUtils.create_equipment`, `UnitSpawner.spawn_local_unit`, `HeroPreviewer._spawn_item_unit`. When a unit's `.unit` file has data keys `mat_to_use`/`mat_slots`/`colors`/`normals`/`MABs`, calls `Material.set_texture(material, slot_name, "<our texture path>")` to swap. This is the only working runtime texture-replace API in this build.
    - [MoreItemsLibrary](https://steamcommunity.com/sharedfiles/filedetails/?id=1422758813) — registers new entries in `ItemMasterList` so a recolored variant shows up in inventory as a separate equippable item (used by Loremaster's Armoury for shield illusions).
  - **Per-cosmetic asset work (not Lua):**
    1. Custom `.unit` file in our mod referencing the existing mesh + adding the Material-Hijack data block (`mat_slots`, `colors = { ... = "our/path/white_albedo" }`).
    2. Recolored albedo DDS authored in Photoshop / GIMP (one per cosmetic), packaged via `.texture` + `.package` declarations.
    3. `MoreItemsLibrary.register_mod_item(clone_key, base_item, our_unit_path)` at mod load.
  - **Lua side (what `cosmetics_tweaker` would do):**
    1. Add Material-Hijack + MoreItemsLibrary as VMF dependencies.
    2. On boot, register the cloned ItemMasterList entry for each shipped recolor.
    3. Add unlock toggles per character (same pattern as the existing per-career hat unlock UI) so users can enable/disable individual recolored variants.
  - **Reference implementation:** [Loremaster's Armoury](https://github.com/dalokraff/Loremasters-Armoury) does exactly this for shield illusions and weapon skins.
- [ ] **Remove dirt/stains from "Purified" white outfits** — the Chaos Wastes "Purified" cosmetic skins (white recolors awarded from CW challenges) have visible dirt, grime, and stain overlays baked into their diffuse textures, making them look grimy rather than pristine. Goal: create cleaned versions with the dirt layer removed or replaced with a clean albedo.
  - **Loremaster's Armoury does NOT do this.** Repo cloned to `c:\Users\danjo\source\repos\Loremasters-Armoury` ([GitHub](https://github.com/dalokraff/Loremasters-Armoury)). It has "Clean" shield variants (custom heraldry shields without battle damage) and one `Purified` helm retexture (Kerillian HornOfKurnous), but does not touch character body/outfit textures for the vanilla Purified white skins at all.
  - **Approach — same pipeline as "Cloned + recolored cosmetics" item above:**
    1. Extract vanilla Purified outfit diffuse textures via `vt2_bundle_unpacker`.
    2. Edit in Photoshop/GIMP to remove the dirt/stain layer from the albedo (likely a multiply/overlay layer or painted directly — need to inspect the DDS to determine).
    3. Package cleaned diffuse as `.texture` + `.package` in cosmetics_tweaker.
    4. Create `.unit` files with Material-Hijack data keys (`mat_slots`, `colors`) pointing to the cleaned textures, referencing the original mesh.
    5. Register as new `ItemMasterList` entries via MoreItemsLibrary so they appear as separate equippable variants (e.g. "Purified (Clean)" alongside the vanilla "Purified").
    6. Add unlock toggles in cosmetics_tweaker settings UI.
  - **Dependencies:** Material-Hijack, MoreItemsLibrary (same as recolored cosmetics).
  - **Key reference:** Loremaster's Armoury `utils/funcs.lua` — `apply_new_skin_from_texture()` uses `Material.set_texture(mat, slot_hash, texture_resource)` with three slots: diffuse (`texture_map_c0ba2942` / `texture_map_64cc5eb8`), combined/MAB (`texture_map_0205ba86` / `texture_map_abb81538`), normal (`texture_map_59cd86b9` / `texture_map_861dbfdc`). Armor uses the second set of hashes.
  - **Open questions:**
    - Which characters have Purified outfits? Need to enumerate via `/probe_cosmetics` or search `ItemMasterList` for "purified" skin keys.
    - Is the dirt painted directly into the diffuse, or is it a separate texture channel (e.g. combined/MAB map)? Inspect extracted DDS to determine editing strategy.
    - Can we swap just the diffuse and leave normal/combined unchanged, or does the dirt appear in multiple maps?

## Illusions & Icons
- [ ] **Custom illusion icons** — all custom illusions (`ct_es_mace_gk_shield_01`, `ct_we_spear_shield_es_*`, `ct_es_deus_we_*`, `ct_es_heavy_spear_deus_*`) use placeholder generic icons (`weapon_generic_icon_staff_3` / `icon_wpn_empire_shield_01_t1_mace`). Need to extract vanilla weapon icons from the game to understand the format/resolution, then create unique icons for each custom illusion. Investigate how icons are referenced (`hud_icon` vs `inventory_icon`), what atlas they live in, and whether runtime injection of new icon textures is possible or if we need to reuse existing icon keys.
- [ ] **Free weapon illusion/skin swap from inventory** — let the inventory menu pick any illusion/skin available to the weapon type without going through Okri's "apply illusion" flow (and without consuming a one-time illusion). Show all illusions for that weapon as selectable options inline on the weapon card.

## Glow Maps

### Phase 1 — DONE (v0.8.6 → v0.8.37)
**All 4 weapon glow families fully working through one UI** (verified empirically v0.8.37):
- `_runed_02..06` themed Veteran (purple/gold/red/green/blue): rune_emissive_color via template mutation
- `_runed_01` Stylish loot-chest white-glow (~160 weapons): rune_emissive_color via custom-template injection at spawn_inventory_unit
- `_magic_02` Shyish-Infused (Versus rewards): 5 versus channels via template mutation on `versus`
- `_magic_01` Weavebound (WoM Athanor): 5 versus channels via custom-template injection (no vanilla template)

**Settings UI**:
- Override toggle [checkbox]
- Glow Color [dropdown: Default / White / Purple / Gold / Red / Green / Blue]
- Advanced: Per-Channel (Magic family)
  - Master Brightness ×
  - Use Per-Channel Colors [checkbox]
  - Lower Gradient Color, Upper Gradient Color, Dots Color (each Default + 6 colors)
  - 6 per-channel brightness multipliers (× 0.0–5.0; 0 SKIPS that channel)

**"Default" preset** = SKIP that variable, vanilla's native value passes through. New default for all 4 dropdowns so enabling the override doesn't change anything until the user picks a color.

### Old Phase 1 — DONE (v0.8.6 → v0.8.16)
- Master toggle + plain-color preset dropdown (Purple / Gold / Red / Green / Blue) under "Weapon & Item Appearance"
- Hook all three `apply_material_settings` copies (`GearUtils`, `_G`, `CosmeticUtils`) using TEMPLATE MUTATION (mutate `MaterialSettingsTemplates[name].x/y/z` to preset values, call vanilla, restore). 1P + 3P + ammo + projectiles + pickups + previewer all painted via vanilla's own write path.
- 1P verified working empirically (v0.8.16). Earlier hook_safe-overlay approach (v0.8.4-v0.8.15) only painted 3p reliably; 1p silently rejected the second write.
- Documented in `memory/reference_vt2_weapon_glow_system.md` as the verified canonical pattern
- Limitation: requires re-applying a cosmetic / re-equipping the weapon to take effect on currently-equipped weapons. Live re-paint not implemented.

### Probe results (v0.8.22-dev `/glow_scan` — for reference)

| Mesh family | Status | Working variable(s) | Channel role |
|---|---|---|---|
| `_runed_02..06` (Veteran themed: purple/gold/red/green/blue) | ✅ Shipped | `rune_emissive_color` (probe #8) | Single channel drives the rune emission |
| `_magic_02` (Shyish-Infused, Versus rewards) | ✅ Shipped | versus 5-channel set (probe #50-54) | 4 main channels (glow_high/low + smoke_high/low) drive gradient; color_dots controls particles |
| `_magic_01` (Weavebound, WoM Athanor) | ✅ Shipped | SAME versus 5-channel set | 50+51 (`color_glow_*`) = lower gradient; 52+53 (`color_smoke_*`) = upper gradient; 54 (`color_dots`) = particles |
| `_runed_01` (Stylish, loot-chest white-glow Veteran) | ✅ Shipped | `rune_emissive_color` (probe #8) | Same variable as themed; "white" IS that variable set to white HDR |

### Open

- [ ] **Live re-paint / faster refresh** — settings changes currently require re-equipping the weapon, sometimes a full unequip-and-different-weapon-swap to fully refresh stale visuals. v0.8.7-v0.8.9 tried walking spawned units; that destabilized hand-mesh visibility on inspect and 1P state. Reverted in v0.8.10. **Safer approach for next attempt:** hook the wield event (`SimpleInventoryExtension.wield` / `_wield_slot`) so we re-apply only at the moment a unit becomes visible — never touching sheathed units that are in some half-bound state. Could combine with re-calling `apply_material_settings` (vanilla) on visible units only, leveraging the same template-mutation hook that already does the safe write.
- [ ] **"Add glow to non-glowy weapons"** — user asked if we can enable glow on weapons that don't have it natively. Answer: not from Lua alone. The emissive shader uniforms only produce visible output if the weapon's mesh material exposes them, and that's defined in the .unit/.material asset, not at runtime. `Unit.set_vector3_for_materials` silently no-ops on non-glow meshes (verified via `/glow_scan`). **Practical workaround**: every Veteran weapon has a `_runed_01` Stylish mesh variant — equipping that illusion + the override gives the same effect. Could automate via a "Make Glowy" toggle in `_register_custom_illusions` that surfaces the `_runed_01` mesh as a one-click toggle on every weapon (already accessible via vanilla's illusion picker if owned, but a one-click would be nicer). Won't help for weapons whose family doesn't have a `_runed_01` Stylish variant authored — those need new asset work.
- [ ] **Husks (other players' 3p weapons in coop)** not covered — they live on `simple_husk_inventory_extension`. Walk peer player_units, look up their husk inventory, paint the same way.
- [ ] **Per-skin custom RGB picker** (Phase 2 UI): rather than a single global color, let users set per-weapon-key colors on the customization screen. Persistence in mod settings keyed by `skin_key`. Build on top of the verified substrate.

## Other
- [ ] **3rd person mod** — enable 3rd person camera view so players can see their character model and cosmetics in gameplay

## Cross-character cosmetic weapon swap (planned 2026-05-23)

- [ ] **Cross-character cosmetic weapon swap** — let players equip another character's weapon MODEL on a functionally-identical native receiver weapon, purely cosmetically. Example: Bardin's one-handed axe model rendered on Saltzpyre's falchion-family one-hander; gameplay, stats, traits, and item identity stay 100% on the receiver's native weapon (it's still mechanically a falchion). Only the visible mesh (and any per-mount sub-meshes — e.g. shield arm, offhand pistol) is overridden.

  ### Origin
  Scoped 2026-05-23 as part of the wt direction reversal. weapon_tweaker is removing identical-functional cross-character ports (cases where the receiver already has a native weapon in the same functional family); those wishes are not gameplay needs, they're cosmetic preferences and belong here. See `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua` top-of-file comment block and the repo-root `CLAUDE.md` mod-table entries for wt + cosmetics_tweaker.

  ### Scope
  - Surface: per-weapon picker on the customization screen (same window family as the existing illusion / offhand pickers), one extra "use another character's model" row that lists eligible source weapons (i.e. weapons from other characters that map cleanly onto this receiver weapon's functional family).
  - Eligibility table: hand-curated list of `(receiver_weapon_key, source_weapon_key)` pairs. Start with the set being removed from wt (the identical-functional ports). Extend as user requests come in.
  - Per-receiver scaling: each `(receiver, source)` pair carries a scale multiplier (similar to wt's `_weapon_scale_overrides`) so the borrowed model sits proportionally on the receiver's body — e.g. a Bardin-scaled axe shrunk to look right on Saltzpyre's hand.
  - Per-receiver grip offsets: each pair carries grip-position adjustments (translation in weapon-local space, similar to wt's `_weapon_grip_offsets`) so the hand bone lines up with the borrowed model's grip mesh, not its centroid.
  - Multi-mount aware: if the receiver weapon has independent hands (sword+shield, dual-wield, rapier+pistol), the cosmetic-swap row should respect the existing per-hand picker shape — i.e. picking a cross-character model on the right hand doesn't clobber a separately-picked left-hand illusion.

  ### Out of scope
  - No gameplay changes. Traits, stats, properties, damage profiles, action sets — all of those stay on the receiver weapon. This is purely a visual override.
  - No 3P animation remap work. Because the receiver weapon is unchanged mechanically, the receiver's native 3P state machine is already wired; we're only replacing the mesh. (Contrast with wt, which does need 3P anim remap because wt actually lets weapons cross over.)
  - No cross-skeleton porting. The target weapons in this feature already exist in the receiver's native lineup — we're only swapping the visible mesh on a weapon that's mechanically native.

  ### Implementation sketch
  - Eligibility table in a new file (e.g. `_xchar_cosmetic_pairs.lua`) keyed by receiver weapon key.
  - New override layer in the existing `BackendUtils.get_item_units` hook chain — after offhand selection, after LA paint, but before final return — that swaps the unit paths to the chosen source weapon's units if a cosmetic swap is active for this `backend_id`.
  - Scale + grip applied via the same mechanism `weapon_tweaker` uses on its cross-character ports (`Unit.set_local_scale` on the spawned attachment unit + grip offset matrix on the attachment node).
  - Persistence: VMF settings keyed by `backend_id`, same pattern as `_offhand_selection`.
  - Husk sync: cross-character cosmetic swaps must propagate to other peers (otherwise teammates see the receiver's native model while the local player sees the swap). Reuse the `cos_la_apply` RPC family — already handles per-hand husk mesh swap.

  ### Open questions
  - **UI affordance** — second picker row vs nested into the illusion row? Probably second row for discoverability, especially because the eligibility list is small per weapon.
  - **DLC gating** — if the source weapon is DLC-locked and the user doesn't own that DLC, do we still let them use the model? Probably no (consistent with the DLC ownership gate the rest of cosmetics_tweaker respects), but verify with the user before shipping.
  - **First-person view** — does the local player see the borrowed model in 1P, or stay on the receiver's native 1P mesh? 1P is universal so showing the borrowed model is technically fine, but it may break user expectations ("I picked a falchion, why do I see an axe in my hand?"). Default to local 1P matches the visible 3P; offer a toggle if user feedback wants it.
  - **Eligibility curation source** — do we lift the list directly from wt's pre-reversal cross-character port table, or hand-pick from scratch? Start by lifting the removed entries from wt; extend later.
