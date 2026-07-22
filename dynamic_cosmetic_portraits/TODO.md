# Dynamic Cosmetic Portraits — Feature To-Do

> **REFERENCE ONLY — not current status.** Unchecked and completed entries may
> be stale. GitHub Issues is the sole current tracker; retain this file only for
> design evidence that is not yet captured in an issue.

## Currently shipped (Kruber Mercenary, 11 portraits)

### Hats (9)
- [x] `mercenary_hat_0001` — Estalian Conquistador
- [x] `mercenary_hat_0003` — Plumed Horseshoe
- [x] `mercenary_hat_0004` — Morr's Mask
- [x] `mercenary_hat_0006` — Stirland Tri-plume
- [x] `mercenary_hat_0007` — Courtier's Crest
- [x] `mercenary_hat_0009` — Veteran's Scars
- [x] `mercenary_hat_1001` — Marienburg Bicorne
- [x] `mercenary_hat_1002` — Marshal Ludenwald's Favourite Hat (Hellequin)
- [x] `mercenary_hat_1003` — Wolverheart Crown

### Outfits (2 — override hat portraits)
- [x] `skin_es_mercenary_1003` — Felix Jaeger
- [x] `skin_es_default` — Champion of Ubersreik (VT1)

## Next portraits (Kruber Mercenary, source images already in workspace)

`D:\Game Mods\Vermintide 2 modding\` already has authored "Kruber Portrait
(<Name>).png" sources at 110×130 for several Kruber hats not yet wired up.
Each one follows the verbatim-110×130 workflow (see `DEVELOPMENT.md`).

- [ ] `mercenary_hat_0000` — Reikland Griffonplume
- [ ] `mercenary_hat_0002` — Lucky Horseshoe
- [ ] `mercenary_hat_0005` — Sellsword's Twinplume
- [ ] `mercenary_hat_0008` — Rakish Leatherbrim
- [ ] Others as authored — match against `CHARACTER_COSMETIC_CATALOG.md`.

## Other Kruber careers

- [ ] **Huntsman portraits** — `huntsman_hat_*` set. Profile is
  `SPProfiles[5].careers[2]`.
- [ ] **Foot Knight portraits** — `knight_hat_*` set. Profile is
  `SPProfiles[5].careers[3]`.
- [ ] **Grail Knight portraits** — `qknight_hat_*` (and the "Champion of
  Ubersreik" pattern doesn't exist for GK; it's its own outfit story).
  Profile is `SPProfiles[5].careers[4]`.

## Other characters

Not started. Each requires:

1. Authoring the source 110×130 PNGs (Photoshop / AI character-consistency
   pipeline), then generating the HUD/small masked variants and rebuilding the
   private portrait atlas through `tools/add_portrait.ps1`.
2. Generalising `_get_kruber_merc_hat_key()` / `_get_kruber_merc_skin_key()`
   to accept a career name and the corresponding `SPProfiles[idx].careers[idx]`
   pointer.
3. Adding per-character maps (or a single nested map keyed by career_name).

Characters and starting careers (the ones with `skin_*_default` = "Champion
of Ubersreik" outfits — natural starting point):

- [ ] Bardin Goreksson — Ranger Veteran (`dr_ranger`, `SPProfiles[2].careers[1]`)
- [ ] Victor Saltzpyre — Witch Hunter Captain (`wh_captain`, `SPProfiles[3].careers[1]`)
- [ ] Kerillian — Waystalker (`we_waywatcher`, `SPProfiles[4].careers[1]`)
- [ ] Sienna Fuegonasus — Battle Wizard (`bw_adept`, `SPProfiles[1].careers[1]`)

## Code cleanup

- [x] **Portrait render-path lists assert parity.** Issue #526 split medium
  standalone materials from HUD/small atlas sprites; runtime and offline tests
  now reject a map entry with no matching render path.
- [ ] **Generalise `_get_kruber_merc_*_key()`** to a single helper that
  takes a `career_name` and a profile/career index pair. Required before
  adding any other career.

## Known issues (defer)

- [ ] **Smallest portrait size uses a different source image in some spots.**
  In certain UI surfaces, the smallest portrait variant (60×70) appears
  to draw from a separate underlying image rather than a downscale of
  the medium portrait — so the custom portrait doesn't propagate there.
  Current asset pipeline (`tools/add_portrait.ps1`) derives the 60×70
  via bicubic-resize + borrowed alpha from `small_portrait_kruber_mercenary_hat_0001.png`,
  which assumes one shared small-size texture per portrait. Need to
  identify which surfaces consume a distinct small-size asset and
  author/wire those separately. Not blocking — file under "for later".
- [ ] **Killfeed portrait icon doesn't update.** The small portrait
  shown in the killfeed (player-name row when downed/killed/revived)
  still renders the vanilla hat-keyed texture. May be the same
  separate-small-source issue above, or may be a different code path
  entirely (killfeed could be reading a hat-keyed material directly
  rather than going through `career_settings.portrait_image` /
  `picking_image`). Investigate via `portrait_dump` while a killfeed
  entry is on screen.
- [ ] **Bot portraits in CW / Versus menus show campaign cosmetics,
  not the mode's actual loadout.** In Chaos Wastes and Versus menu
  surfaces, a bot character's portrait reflects whichever hat/outfit
  the player last equipped in **campaign** mode — not the cosmetic
  the bot is actually wearing in CW/Versus. In-mission, the same bot
  does get the correct portrait for its CW/Versus loadout, so the
  detection works for live player_units; the gap is in the menu-side
  lookup, which appears to read the campaign profile's cosmetic
  selection rather than the current mode's. Investigate which
  cosmetic-source the menu surface is reading from when the
  character is a bot (vs. a player) in CW/Versus.

## Out of scope (deferred indefinitely)

- **Cross-character hat unlocks for portraits.** If/when cosmetics_tweaker
  enables cross-character hat wearing (which it currently doesn't because
  of skeleton-attachment-node mismatches), this mod would need to match
  hats it wasn't designed for. Not a priority — wait for cosmetics_tweaker
  to ship that feature first.
- **Frame customisation.** The hexagonal frame is part of the baked PNG.
  Switching to vanilla-frame-on-top + custom-portrait-underneath would
  require widget-level work beyond the career_settings swap. Out of scope.
