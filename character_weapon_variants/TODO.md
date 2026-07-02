# Character Weapon Variants — To-Do

## Completed
- [x] **First variant: Weave Forged Axe and Shield** — `cwv_es_axe_shield` (magic rarity, base template) for Kruber (Merc/Huntsman/FK). Mainhand: Saltzpyre's weave hatchet, offhand: Kruber's weave CW shield.
- [x] **Veteran Axe and Shield** — `cwv_es_axe_shield_exotic` (unique/veteran rarity) with Opportunist trait, block cost reduction, power vs skaven. Red background, cosmetics menu, full item behavior.
- [x] **Auto-registration** — all variant weapons register automatically on `StateInGameRunning.on_enter`. Stable backend IDs prevent duplicates across sessions.
- [x] **Cross-character weapon unlock** — Saltzpyre's one-handed axe (`wh_1h_axe`) unlocked on all Kruber careers.
- [x] **Cross-character greatsword illusions** — Saltzpyre's greatsword models available as illusions on Kruber's greatsword and vice versa.
- [x] **Imperial Longsword** — `cwv_es_longsword` (base, power 5) and `cwv_es_longsword_veteran` ("Halfling Splitter", exotic). Custom `imperial_longsword_template` with -15% damage, +15% speed, +15% cleave, -15% stagger. Model scaling: 1h sword Z+15%, greatsword X=0.65 Z-15%.

## Tuskgor Javelin polish (cwv_es_javelin / cwv_wh_javelin)
- [x] **Thrown javelins stick + be pickable like throwing axes** (v0.1.70) — `tuskgor_javelin_template` clone now strips javelin's `link/wall_nail/flow_event_on_walls=teleport_out` from `throw_charged.impact_data` and substitutes throwing-axe's `link_pickup = true` + `pickup_settings = { use_weapon_skin, link_hit_zones }`. No custom `Projectiles.*` clone needed — `Projectiles.javelin` and `Projectiles.throwing_axe` are nearly identical (both `static_impact_type = "raycast"`); the difference lives entirely in the action's impact_data.
- [ ] **Stuck/in-flight projectile model** — still uses the slim elf javelin model (`projectile_units_template = "javelin"`). Anvil package ships only the held `_3p` boar spear unit, no `prj_*_3ps`. To get a boar-spear-shaped projectile in flight + stuck, need to author/inject a `prj_emp_boar_spear_*_3ps` model unit. Low priority.
- [x] **Hide the 3P offhand spare-spear duplicate WITHOUT setting `ammo_unit = invisible_weapon`** (v0.1.322) — runtime hide via `Unit.set_unit_visibility(slot_data.left_ammo_unit_3p, false)`. Two hook sites: (1) extended `SimpleInventoryExtension._wield_slot` POST — catches the wield-time visibility set at `simple_inventory_extension.lua:2153`; (2) extended `SimpleInventoryExtension.show_third_person_inventory` POST with `show=true` — catches camera FP→3P toggles that vanilla uses to re-show 3P inventory. Both gated on backend_id matching `^cwv_e[sw]_javelin_`. 1P offhand spare left visible (user only complained about 3P).
- [ ] **Stuck javelin sits too deep in the wall** — v0.1.258/v0.1.263's pull-back math (`pos - Quaternion.forward(rot) * _TJ_VISUAL_PULL_BACK_M`) did not visibly move the spawned boar spear visual. Reverted to 0 in v0.1.314. Root cause unknown. Suspects: (1) the parent throwing-axe pup's world rotation doesn't have its forward axis aligned with the spear's pointing direction — `Quaternion.forward(rot)` may be a sideways or vertical axis, not "into the wall"; (2) the parent unit's world_position is offset from the actual contact point, so subtracting along forward overshoots into space we can't see; (3) the visual spawned at the adjusted pose, but the link_pickup system snaps it back to the parent on the next frame. Debug: log `Quaternion.forward(rot)` + parent world_position + computed adjusted pos at spawn time; also check whether the boar spear's local origin is at the tip vs the midpoint of the model.

## Tuskgor Javelin BOMB SLOT (cwv_grenade_tuskgor_javelin) — v0.1.352-dev, NOT yet verified in-game

New archetype: the FULL javelin weapon (melee stabs + aimed throw) as a ONE-SHOT consumable in `slot_grenade`, full size. v0.1.353-dev reworked it from a grenade-template clone to a `javelin_template` clone (max_ammo=1 + destroy_when_out_of_ammo). Acquired via a new grenade pickup (`cwv_tuskgor_javelin_bomb`) injected into `Pickups.grenades` (~15% pool share, toggle `enable_cwv_tuskgor_javelin_bomb`, default ON) OR the chat command **`/cwv_give_javelin`** (instant grant to bomb slot, for testing). Throw uses `kind="thrown_projectile"` direct impact (no explosion); buffed `thrown_javelin` damage profile (armour pierce, cleave 2.5 → multi-pierce, shield_break, headshot 3.0×, 2.5× power); melee stabs buffed 2.5×. Code: `character_weapon_variants.lua` `do ... end` block right after `_create_tuskgor_javelin_template()`.

- [ ] **KEY OPEN QUESTION:** does the grenade SLOT cleanly wield a full ranged-template moveset (hold + melee-stab + aim-throw), or does the slot's quick-throw input interfere? Test with `/cwv_give_javelin`. If the slot won't drive the moveset, may need a slot/input workaround.
- [ ] **VERIFY in-game (DoD gate):** pickup spawns + is interactable; melee stabs work + feel right; aim+throw fires the boar-spear projectile; armour/shield/multi-pierce + headshot/monster scaling all behave; held boar-spear mesh renders at full size; throw consumes the item (gone).
- [ ] **VERIFY multiplayer:** remote husk view shows the spear (reads ItemMasterList.right_hand_unit); a client picking up a host-spawned javelin equips + throws it correctly (item_names / pickup_names index parity assumes all peers run the same CWV build).
- [ ] **Tune damage** — 2.5× power / cleave 2.5 / headshot 3.0× / armour ≥1.5 are first-pass guesses; balance against "as strong as the user wants" after testing. Knobs: `_TJB_DAMAGE_MULT`, `_TJB_CLEAVE`, `_TJB_HEADSHOT_BOOST`, `_TJB_DEPTH`, `_TJB_THROW_SPEED`, `_TJB_SPAWN_SHARE`.
- [ ] **World pickup model** — interim is the frag-bomb pup (`pup_grenade_01_t1`, has interaction actors). Replace with a spear-shaped pickup or the throwing-axe-pup carrier pattern (boar spear attached as a visual child) like the ranged javelin uses.
- [ ] **Held-pose / attachment** — boar spear is mounted on the grenade hand node (`one_handed_melee_weapon.right`) and uses the grenade `to_grenade` wield + overhand throw anim. Orientation may read wrong (2H polearm on a 1H grenade node); consider a polearm attachment + a proper throw windup.
- [ ] **HUD/inventory icon** — interim reuses the bomb icon (`hud_inventory_icon_bomb`); author a javelin icon if desired.

## cwv_es_crossbow polish

Tracks the known polish items that came over from `weapon_tweaker` v0.12.94-dev when the Kruber crossbow port was migrated into CWV as the `cwv_es_crossbow` variant (default-on toggle `enable_cwv_es_crossbow`). These are the reasons the port didn't fit `weapon_tweaker`'s "simple toggle" model — variant ownership in CWV lets each be solved (or explicitly deferred) per the DEFINITION_OF_DONE gate doctrine.

- [ ] **3P grip offsets need adjusting to fit Kruber's Rifle (handgun) animations.** The wield maps `to_handgun` / `to_handgun_noammo` for all 4 Kruber careers, but the crossbow mesh's hand-attachment offsets are tuned for Saltzpyre's crossbow stance — when Kruber holds it with rifle hand placement, the crossbow sits visibly wrong in 3P. Adjust via `right_hand_offset` / `right_hand_scale` (or per-career overrides) until the silhouette reads correctly. Per user 2026-05-26: "rifle animation looks the most natural on the crossbow so far" — keep that anim mapping, just shift the model.
- [ ] **Remove smoke effect on shot.** Vanilla wh_crossbow firing FX include a powder-flash smoke puff that flavors it as Saltzpyre's signature; on Kruber the smoke reads as wrong (no flintlock context). Patch the `action_one.default.fire_action` or whichever sub-action carries the muzzle_flash_unit / particle effect, and null/replace it on the cwv variant. Walk `crossbow_template_1.actions` and find the FX reference.
- [ ] **3P weapon model is missing the bolt on the crossbow.** Vanilla crossbow's 3P unit shows a nocked bolt in addition to the body; on Kruber's 3P body the bolt is absent (likely an `ammo_unit_3p` attachment-node issue tied to the Saltzpyre-specific body hardpoints). May require custom attachment-node offsets on Kruber's body to render the bolt — investigate, but be prepared that it may not be achievable since Kruber's body doesn't author crossbow-specific bolt nodes.

## Weapon Variants (Planned)
- [ ] **Enumerate all viable cross-character combos** — catalog which weapon+shield combinations across characters make sense as curated variants, case-by-case.
- [ ] **Animation remapping** — verify Bardin's axe+shield template animations play correctly on Kruber's skeleton. May need 1P/3P anim redirects (same system as weapon_tweaker).

### Hammer vs mace differentiation toggle (planned 2026-05-23)

Optional VMF toggle. When enabled:

- **Hammers** — more damage, less attack speed, less cleave.
- **Maces** — less damage, more attack speed, more cleave.

When disabled, hammers and maces share moveset stats (current behavior).

**Why this matters for CWV variant identity:** several cross-character CWV variants are mechanically identical to their receiver-native counterparts without this toggle and are differentiated **only** by 1P wield aesthetics:

- `warpriest_hammer` on Kruber — same moveset as Kruber's mace family.
- `es_maul` on Kruber — also overlaps with Kruber's mace family.

With the toggle on, those variants gain a hammer profile distinct from the native mace profile — so the variant feels like a genuine new option, not a re-skin. Without the toggle, the 1P differentiation is still preferred (see `DEVELOPMENT.md` "Design intent"); the toggle extends differentiation to mechanics.

### Per-family 5-modded-instance scaffolding (planned 2026-05-13)

Going forward, every CWV weapon family ships:

- **1 blacksmith template** — `rarity = "default"`, `power_level = 5`, unbreakable. Crafting / new-player starter. Already shipped for several families (`cwv_es_axe_shield`, `cwv_es_longsword`).
- **5 modded-rarity instances** — each a separate def with pre-baked trait + 2 properties. `rarity = "modded"` (order=4, mirrors exotic → unlocks customization tabs → player can re-roll).

**Naming rule (load-bearing):**
- Item **base name** = the weapon kind (e.g. "Axe and Shield").
- Instance **name** = whatever cosmetic/illusion is equipped on it (decided at cosmetic-pick time, not at def-creation time).
- **Do NOT pre-name instances by trait/property combo.** Display name follows the cosmetic + Warhammer Fantasy lore inspiration from the model's iconography (most vanilla weapons aren't lore-named by Fatshark — user does that work).

**Two universal shield archetypes** (first two slots of every shield family — cover ~90% of shield builds):

**Instance 1 — Defensive (stagger / survivability):**
```lua
traits     = { "melee_counter_push_power" },          -- Opportunist
properties = { power_vs_skaven = 1, block_cost = 1 },
```
Opportunist hits stagger breakpoints; Power vs Skaven catches Plague Monk stagger; Block Cost Reduction is mandatory shield survivability at high difficulty.

**Instance 2 — Offensive crit:**
```lua
traits     = { "melee_attack_speed_on_crit" },          -- Swift Slaying
properties = { attack_speed = 1, crit_chance = 1 },
```
Base 5% + trinket 5% + weapon 5% = 15% crit → Swift Slaying ~90% uptime. Most powerful generic melee trait; no enemy-type bias. Particularly strong on Foot Knight (innate stagger means he doesn't need stagger talents).

**Remaining 3 slots per family:** career- or build-specific. Require user input + breakpoint research per family — don't invent. NEVER fabricate breakpoint claims; crit-dependent breakpoints are NOT "reliable" unless paired with a guaranteed-crit talent. Damage and stagger breakpoints are separate tables — be explicit about which one a build targets. If unknown, ask the user or check the Royale w/ Cheese community breakpoint spreadsheet. Scope is regular Cataclysm only (not C1/C3).

**Modded rarity registration:** currently lives only in `crafting_in_modded/modded_rarities.lua`. For CWV to use standalone, either self-register inside CWV with `if not RaritySettings.modded then ... end` guard, or extract `modded_rarities.lua` into a shared lib mod both `cim` and CWV depend on (out of scope until cross-mod pressure forces it).

**How to apply:** walk one weapon family at a time. Confirm trait/property choices with user before authoring defs. Don't write display names or descriptions until cosmetic is picked.

### Stance-toggle ranged-melee variants (2026-05-11 batch)
Each entry below uses the `cwv_es_musket` recipe (`reference_cwv_stance_toggle_recipe.md`): two templates registered, special-key destroys-and-rewields with a stance-flag flip, `BackendUtils.get_item_template` hook returns the alt template. Order roughly by implementation cost (similar bases first, novel combos last).

- [ ] **Kruber Javelin + Shield** — `cwv_es_javelin_shield`. **In progress** (first item, kicks off the batch). Ranged stance = Tuskgor Javelin behavior (clone of `tuskgor_javelin_template`, boar spear visual). Melee stance = `one_handed_spears_shield_template` clone with reduced range_mod (~0.85x vanilla), boar spear in right hand, empire shield 01 in left. Shorter melee reach than vanilla 1H spear+shield. Empire Soldier careers only.
- [ ] **Bardin Javelin** — `cwv_dr_javelin`. Tuskgor Javelin equivalent for Bardin. Mirror of `cwv_es_javelin` def with `character = "dwarf_ranger"`. 3P anim verification needed for dwarf skeleton (boar spear throw events); 1P universal per the rule. Worth doing BEFORE the javelin+shield variant — proves the base works on Bardin before adding shield complexity.
- [ ] **Bardin Javelin + Shield** — `cwv_dr_javelin_shield`. Same stance-toggle pattern as Kruber. Melee stance uses Bardin's `1h_axe_shield` rig as the spear+shield analog (Bardin has no native spear+shield) OR force the Saltzpyre 1H sword+shield template if dwarf skeleton plays it. Decision needed.
- [ ] **Bardin Throwing Axe + Shield** — `cwv_dr_throwing_axe_shield`. Ranged stance = vanilla Bardin throwing axes (`dr_throwing_axes_template` or its equivalent — confirm key) with shield in left hand on melee stance only. Melee stance = vanilla Bardin `dr_1h_axe_shield`. Bardin's natural fit since he already has throwing axes AND axe+shield in vanilla — least novel rig.
- [ ] **Kruber Throwing Axe** — `cwv_es_throwing_axe`. Cross-character throwing axe for Kruber, using "specially scaled axes that Saltzpyre has" as the visual base. **Open question**: which Saltzpyre item provides the throwing-axe model? Vanilla Saltzpyre has no native throwing axe — confirm the user means a LoremastersArmoury / modded item or a different vanilla weapon mistakenly attributed to Saltzpyre. Default assumption: clone Bardin's throwing axe with a scaled-up rig.
- [ ] **Saltzpyre Throwing Axe** — `cwv_wh_throwing_axe`. Same base axe + scaling as the Kruber variant. Saltzpyre cross-character access only — clarify base model with user.
- [ ] **Kruber Throwing Axe + Shield** — `cwv_es_throwing_axe_shield`. Stance toggle: ranged = Kruber throwing axe (above), melee = `es_1h_axe_shield` (Kruber has this natively). Empire skeleton plays axe+shield events natively, lowest-risk melee stance.
- [ ] **Saltzpyre Throwing Axe + Shield** — `cwv_wh_throwing_axe_shield`. Stance toggle: ranged = Saltzpyre throwing axe (above), melee = `wh_1h_axe_shield` or `wh_1h_sword_shield` — pick whichever has the closer-to-axe melee feel. Saltzpyre's skeleton plays both.

## Infrastructure
- [ ] **Crafting menu** — UI for obtaining variant weapons in-game instead of console commands. Could live in this mod or integrate with cosmetics_tweaker's planned crafting UI.
- [ ] **Custom inventory icons** — each variant needs a unique icon to distinguish from similar vanilla weapons. Investigate icon format, resolution, atlas injection.

## Integration
- [ ] **weapon_tweaker coordination** — when both mods are active, weapon_tweaker should defer to character_weapon_variants for combos that have a purpose-built variant instead of raw cross-career unlock.
- [ ] **cosmetics_tweaker offhand options** — when both mods are active, cosmetics_tweaker should register per-character offhand illusion options for variant weapons (e.g. Kruber's shield roster for `cwv_es_axe_shield`).
