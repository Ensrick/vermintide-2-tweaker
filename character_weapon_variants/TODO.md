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

## Weapon Variants (Planned)
- [ ] **Enumerate all viable cross-character combos** — catalog which weapon+shield combinations across characters make sense as curated variants, case-by-case.
- [ ] **Animation remapping** — verify Bardin's axe+shield template animations play correctly on Kruber's skeleton. May need 1P/3P anim redirects (same system as weapon_tweaker).

## Infrastructure
- [ ] **Crafting menu** — UI for obtaining variant weapons in-game instead of console commands. Could live in this mod or integrate with cosmetics_tweaker's planned crafting UI.
- [ ] **Custom inventory icons** — each variant needs a unique icon to distinguish from similar vanilla weapons. Investigate icon format, resolution, atlas injection.

## Integration
- [ ] **weapon_tweaker coordination** — when both mods are active, weapon_tweaker should defer to character_weapon_variants for combos that have a purpose-built variant instead of raw cross-career unlock.
- [ ] **cosmetics_tweaker offhand options** — when both mods are active, cosmetics_tweaker should register per-character offhand illusion options for variant weapons (e.g. Kruber's shield roster for `cwv_es_axe_shield`).
