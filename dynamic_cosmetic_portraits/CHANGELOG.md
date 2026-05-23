# Changelog — Dynamic Cosmetic Portraits

This mod was split out of `cosmetics_tweaker` on 2026-05-06. The full
pre-split development history of the portrait system (v0.7.37–v0.7.102 and
the v0.8.0–v0.8.4-dev cosmetics_tweaker line) lives in
[../cosmetics_tweaker/CHANGELOG.md](../cosmetics_tweaker/CHANGELOG.md) — keep it as the
authoritative archive of how the system was researched and stabilised.

## [2026-05-20 v0.1.7] — Add Sellsword's Twinplume portrait
### Added
- Kruber Mercenary hat `mercenary_hat_0005` (Sellsword's Twinplume). Generated via `tools/add_portrait.ps1` from the 110x130 source PNG; alpha mask borrowed from the canonical `mercenary_hat_0001` reference.

## [2026-05-08 v0.1.6] — Fix Spoils of War crash + cover all known portrait-bearing views
### Fixed
- **Crash on Spoils of War loot menu** with same error shape as v0.1.5 (`Material 'portrait_kruber_mercenary_hat_1002' not found in Gui` at `ui_passes.lua:134`). Root cause clarification: Lua 5.1's **tail-call elimination** strips the inner-factory frames (`view_settings.ui_renderer_function` → `IngameUI:create_ui_renderer`) from the call stack. So when `hero_view_state_loot.lua:271` calls `self.ingame_ui:create_ui_renderer(world)`, VMF's frame-4 traceback parser lands on `hero_view_state_loot.lua`, NOT on `ingame_ui_settings.lua`. The v0.1.5 fix happened to mask the pause-menu case for a different reason (HeroView's caller chain may not have been fully tail-called), but did not generalize.
- Added every portrait-bearing entry-point file we could identify from the VT2 source's `create_ui_renderer` call sites: `hero_view`, `hero_view_state_loot` (Spoils of War), `hero_view_state_store` (Emporium), `hero_view_state_weave_forge` (Athanor), `start_game_state_settings_overview`, `store_item_purchase_popup`, `store_welcome_popup`, `game_mode_map_deus` (Chaos Wastes map), and `ui_manager`. Plus the existing `ingame_ui`, `ingame_ui_settings`, `level_end_view_base`, `level_end_view_versus`.

## [2026-05-08 v0.1.5] — Fix pause-menu crash (inject into ingame_ui_settings + level_end)
### Fixed
- **Crash on clicking any pause-menu button** with `Material 'portrait_kruber_mercenary_hat_0009' not found in Gui` at `ui_passes.lua:134`. Root cause: VMF's `inject_materials` keys off the basename of the lua file that called `UIRenderer.create`, and we only registered `"ingame_ui"`. The pause menu's HeroView / OptionsView / CharacterSelection / StartMenu / StartGame all get their renderer from `scripts/ui/views/ingame_ui_settings.lua` (lines 648, 650, 726, 728), so those views' Gui handles never received our portrait materials and crashed the moment they tried to draw a unit frame referencing one. Same shape would have hit at end-of-mission via `level_end_view_base` / `level_end_view_versus`.
- Refactored `dynamic_cosmetic_portraits_data.lua` to derive `ui_renderer_injections` from a single `_texture_names` list and a `_renderer_creators` list, instead of two parallel hand-maintained 33-line literals. Now adding a portrait only requires touching one list (after running `tools/add_portrait.ps1`).

### Renderer creators now covered
- `ingame_ui`
- `ingame_ui_settings` ← **the missing one that caused the crash**
- `level_end_view_base`
- `level_end_view_versus`

## [2026-05-07 v0.1.4] — Codify the workflow against future mistakes
### Added
- **`tools/add_portrait.ps1`** — single-command portrait asset generator.
  Encodes the only correct workflow: medium = source verbatim 110×130, HUD
  and small = bicubic-resize RGB + alpha channel borrowed from the
  `mercenary_hat_0001` reference variants. Generates `.png` / `.texture` /
  `.material` files, verifies output alpha at corners, prints next manual
  steps. Re-running it on Plumed Horseshoe produces functionally identical
  output to v0.1.3 (verified).
- **`CLAUDE.md` at the mod root** — workflow guardrails for AI agents,
  recurring failure modes table, in-game diagnostic command list.
- **DEVELOPMENT.md prominent banner** at the top — points at the script,
  enumerates the failure modes from v0.1.0 / v0.1.1 / v0.1.2 / v0.1.3.
- **Tripwire comments in `dynamic_cosmetic_portraits.lua`** above
  `_PORTRAIT_MATERIALS`, `_hat_portrait_map`, and `_skin_portrait_map`,
  warning that adding entries without running the script first crashes
  in-game with "Material not found in Gui".
- **Tripwire comment in `dynamic_cosmetic_portraits_data.lua`** above
  `custom_gui_textures`.
- **Repo-root `CLAUDE.md`** Key Reference Files updated with the new
  script and child CLAUDE.md.

### Why
Three shipped versions broke the same way (different specific guesses,
same root cause: free-handing the asset pipeline instead of borrowing
the alpha mask from a working portrait). Encoding the workflow in a
script + tripwires + a child CLAUDE.md should make accidental regression
much harder.

## [2026-05-07 v0.1.3] — Plumed Horseshoe alpha-mask fix + correct workflow doc
### Fixed
- **`mercenary_hat_0003` (Plumed Horseshoe) HUD/small overflow.** Both
  v0.1.1 (bicubic resize, no alpha) and v0.1.2 (110×130 verbatim under all
  three names, also no alpha) shipped HUD and small variants without the
  hex/shield-shaped alpha mask that defines the visible silhouette inside
  the in-game frame widget's hex cutout. Without the mask, RGB content at
  the canvas corners pokes past the frame's cutout edge — observed as
  "overflow" in-game. Fix: HUD (86×108) and small (60×70) now use the RGB
  content bicubic-downscaled from the 110×130 source PLUS the alpha channel
  copied verbatim from the corresponding `mercenary_hat_0001` (Estalia)
  reference variant. The medium (110×130) stays as a verbatim copy of the
  source — no mask needed at hero-select size.

### Documentation
- **DEVELOPMENT.md workflow rewritten** with the correct three-step asset
  generation (medium = source verbatim; HUD = resize 86×108 + alpha from
  reference; small = resize 60×70 + alpha from reference). Includes the
  PowerShell snippet that produces all three variants from a single source.
- Earlier doc revisions in v0.1.1 and v0.1.2 had the workflow wrong in
  different ways — neither acknowledged that HUD/small need shaped alpha
  borrowed from a reference portrait.

## [2026-05-06 v0.1.2] — Plumed Horseshoe (still broken — superseded by v0.1.3)
### Added/changed
- Replaced v0.1.1's bicubic-resized HUD/small with verbatim 110×130 copies.
  Still wrong: HUD/small at 110×130 still lack the hex-shaped alpha mask,
  and the engine's scale-down to widget size doesn't add a mask. Overflow
  persisted; fixed in v0.1.3.

## [2026-05-06 v0.1.1] — Plumed Horseshoe portrait (broken — superseded by v0.1.2)
### Added
- `mercenary_hat_0003` ("Plumed Horseshoe") with bicubic-downscaled HUD
  and small variants but no alpha mask. Caused visible content to extend
  past the in-game frame's hex cutout.

## [2026-05-06 v0.1.0] — Initial split from cosmetics_tweaker
### Added
- New standalone mod (Workshop ID `3721036701`, private). Wraps the dynamic
  portrait system that previously shipped inside `cosmetics_tweaker`.
- Includes 10 portrait sets (8 Kruber Mercenary hats + 2 outfits — Felix
  and VT1 Champion of Ubersreik).
- `dynamic_portraits` toggle (default ON).
- `portrait_diag`, `portrait_dump`, `test_portrait` console commands.
- `CHARACTER_COSMETIC_CATALOG.md` moved here (it's exclusively a
  portrait-authoring reference).

### Architecture
Identical to the pre-split design (see ../cosmetics_tweaker/CHANGELOG.md
v0.7.62 entry):
- Single source-of-truth swap of `SPProfiles[5].careers[1].portrait_image`
  and `.picking_image` — every UI surface that builds portrait textures from
  career_settings updates automatically (HUD, hero selection, ESC menu, tab
  overlay, end-of-round, matchmaking).
- `_check_portrait_materials_ready()` probes `Gui.material()` directly,
  since VMF bypasses the `UIRenderer.create` hook used pre-v0.7.52.
- Skin/outfit portraits override hat portraits because outfits replace
  Kruber's head model regardless of equipped hat.

### Carried-over from pre-split
- `_gui_has_material()` and `_flush_log()` are duplicated as locals here
  rather than imported, so this mod has no runtime dependency on
  cosmetics_tweaker.
- `NewsFeedUI:draw` hot-reload safety hook stayed in cosmetics_tweaker —
  it protects illusion/LA atlases, not portrait materials.
- `_get_hat_item_key_for_unit` was deleted (was an orphan).

### Known limitations (post-split)
- Only Kruber Mercenary is covered. Other characters/careers need new
  Photoshop portraits + new entries in `_hat_portrait_map` / `_skin_portrait_map`.
- Hot-reload (Ctrl+Shift+R) is unsafe — engine-level resource locks on
  loaded materials/textures. Always restart VT2 after redeploying.
