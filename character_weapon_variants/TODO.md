# Character Weapon Variants — To-Do

## Completed
- [x] **First variant: Weave Forged Axe and Shield** — `cwv_es_axe_shield` (magic rarity, base template) for Kruber (Merc/Huntsman/FK). Mainhand: Saltzpyre's weave hatchet, offhand: Kruber's weave CW shield.
- [x] **Veteran Axe and Shield** — `cwv_es_axe_shield_exotic` (unique/veteran rarity) with Opportunist trait, block cost reduction, power vs skaven. Red background, cosmetics menu, full item behavior.
- [x] **Auto-registration** — all variant weapons register automatically on `StateInGameRunning.on_enter`. Stable backend IDs prevent duplicates across sessions.
- [x] **Cross-character weapon unlock** — Saltzpyre's one-handed axe (`wh_1h_axe`) unlocked on all Kruber careers.
- [x] **Cross-character greatsword illusions** — Saltzpyre's greatsword models available as illusions on Kruber's greatsword and vice versa.
- [x] **Imperial Longsword** — `cwv_es_longsword` (base, power 5) and `cwv_es_longsword_veteran` ("Halfling Splitter", exotic). Custom `imperial_longsword_template` with -15% damage, +15% speed, +15% cleave, -15% stagger. Model scaling: 1h sword Z+15%, greatsword X=0.65 Z-15%.

## Weapon Variants (Planned)
- [ ] **Enumerate all viable cross-character combos** — catalog which weapon+shield combinations across characters make sense as curated variants, case-by-case.
- [ ] **Animation remapping** — verify Bardin's axe+shield template animations play correctly on Kruber's skeleton. May need 1P/3P anim redirects (same system as weapon_tweaker).

## Infrastructure
- [ ] **Crafting menu** — UI for obtaining variant weapons in-game instead of console commands. Could live in this mod or integrate with cosmetics_tweaker's planned crafting UI.
- [ ] **Custom inventory icons** — each variant needs a unique icon to distinguish from similar vanilla weapons. Investigate icon format, resolution, atlas injection.

## Integration
- [ ] **weapon_tweaker coordination** — when both mods are active, weapon_tweaker should defer to character_weapon_variants for combos that have a purpose-built variant instead of raw cross-career unlock.
- [ ] **cosmetics_tweaker offhand options** — when both mods are active, cosmetics_tweaker should register per-character offhand illusion options for variant weapons (e.g. Kruber's shield roster for `cwv_es_axe_shield`).
