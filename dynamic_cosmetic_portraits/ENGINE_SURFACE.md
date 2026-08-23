# dynamic_cosmetic_portraits - engine contact surface

What vanilla VT2/Stingray does at every seam `dynamic_cosmetic_portraits` (`dcp`)
touches, and why the mod is there. This is the per-mod companion to the subsystem
set in `docs/engine/` (read `docs/engine/README.md` for house style). It does
**not** re-explain a subsystem the engine docs own, and it does **not** duplicate
the mod's `DEVELOPMENT.md` (portrait asset pipeline, renderer-creator key theory,
dead ends) or `CLAUDE.md` (workflow guardrails) - it names each engine seam, cites
the vanilla behavior, and links out. Decompile paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `dcp` line numbers are
`dynamic_cosmetic_portraits.lua` unless noted. `§N` = a `docs/BUG_CLASSES.md`
class; `#N` / "issue N" = a GitHub issue. Grep-verified 2026-07-12 against the
decompile.

`dcp` swaps a career's portrait texture at its source so every UI surface that
displays that character's portrait updates with no per-widget hooking. VT2 builds
every portrait texture name from `career_settings.portrait_image` /
`.picking_image` at display time [src: `scripts/settings/profiles/career_settings.lua`],
so mutating those two fields once flips the HUD unit frame, hero-select, ESC menu,
matchmaking, and end-of-round together. The engine contact is therefore ONE hook
(a per-frame draw callback used only as a "materials ready yet" tick) plus two
data-driven, non-hook seams: the `career_settings` table mutation and VMF's
`custom_gui_textures` material injection. As of v0.1.16-dev it is scoped to Kruber
Mercenary (`SPProfiles[5].careers[1]`).

## Hook table

The primary player-scoped path has four registration sites: the materials-ready
draw tick plus HUD, Tab-list, and score-screen resolution seams. `[safe]` =
`mod:hook_safe` (post-callback, no override). The
career_settings swap and the material injection are NOT hooks (a plain-table
mutation and a VMF data API respectively) and are covered in the subsystem notes.

### Materials-ready tick (per-frame row) (owner doc: `docs/engine/09`)

| Class.method (kind) | Vanilla behavior at the seam | Why dcp hooks it | Trap / invariant |
|---|---|---|---|
| `UnitFrameUI.draw` [safe] `:734` | Draws a player HUD unit frame each frame [src: `scripts/ui/hud_ui/unit_frame_ui.lua:326`] | Call `_sync_portrait_settings()` so the career_settings swap activates on the first frame after the custom resources are resident and the hat/skin is detected (`:734`) | PER-FRAME row, but a cheap no-op once `_portrait_settings_active` flips: `_sync_portrait_settings` early-returns until `_check_portrait_materials_ready()` proves all 24 HUD/small `UIAtlasHelper` rows, the shared atlas material, and all 12 medium standalone materials on one injected Gui. Missing resources fail open to vanilla. `Gui.material(gui, name)` returns nil silently on a missing material in this build (NOT a throw), so the probe MUST inspect the return, not just `pcall` success. This is a readiness TICK only - the actual swap targets the shared `career_settings` table, so player scope is corrected at the consumer seams (issue 435) |

### Local presentation invalidation (non-hook seam)

#925 attaches DCP to the bounded copied library
`_lib_ui_presentation_refresh.lua`. Cosmetics or GUT Dev publishes a successful
local hat/outfit write; DCP drains at most eight events per VMF `mod.update`,
HUD draw, or game-state edge, then performs one `_sync_portrait_settings` call.
Only Mercenary `slot_hat`/`slot_skin` rows are accepted. The writer's exact key
bridges at most sixteen resolver passes while `CosmeticUtils` catches up, after
which the existing resolver owns state again. This adds no engine hook, network
message, persistent loadout cache, or dependency on a sibling mod; absence or
schema conflict preserves prior behavior. See `docs/CROSS_MOD_ARCHITECTURE.md`
"Local presentation invalidation".

## Subsystem notes (how the vanilla flow runs end-to-end, for dcp's cases)

Each note is the minimum needed to read the hook above; the owning `docs/engine`
doc and `DEVELOPMENT.md` carry the full architecture.

### One source swap, every surface (owner: `docs/engine/09`; detail: `DEVELOPMENT.md` "One swap, every surface")

Every VT2 portrait surface derives its texture name from
`career_settings.portrait_image` (`<base>` directly on the HUD, `medium_<base>`
on hero-select, `small_<base>` on matchmaking, etc.) [src: `career_settings.lua`
portrait fields; e.g. `:67`]. `dcp` saves the originals once
(`_original_portrait_image` / `_original_picking_image`, `:445`), then writes the
custom `portrait_kruber_mercenary_<key>` pair into the live table when a tracked
hat/outfit is equipped, restoring the originals when nothing matches or on unload
(`_restore_portrait_settings`, `:428`). These are plain mutable Lua tables - no
hook is needed on any consumer. `_sync_portrait_settings` (`:440`) is driven from
three places: the `UnitFrameUI.draw` tick above, `mod.on_game_state_changed`
(`:738`), and cleanup via `mod.on_unload` (`:749`).

### Cosmetic-key resolution (owner: `docs/engine/06`, feeds `docs/engine/11`)

The equipped hat/skin key comes from `CosmeticUtils.get_cosmetic_slot(player,
"slot_hat" | "slot_skin").item_name` [src: `scripts/helpers/cosmetic_utils.lua:254`],
with a `BackendUtils.get_loadout_item("es_mercenary", slot)` fallback [src: backend]
(`:362`-`:426`), both `pcall`-wrapped and cached into `_last_known_*_key`.
Skin/outfit wins over hat: an outfit replaces the head model regardless of hat, so
`_skin_portrait_map` is consulted first and `_hat_portrait_map` is the fallback
(`:459`-`:464`). The maps are pure lookup tables that ASSUME the `.png`/`.texture`/
`.material` assets already exist on disk - adding a key without running
`tools/add_portrait.ps1` first crashes "Material not found in Gui" (file header
banner; `CLAUDE.md`).

### VMF material injection + renderer-creator keys (owner: `docs/engine/09`)

The end-of-round score creates each row with `UIWidgets.create_portrait_frame`
and passes `career_settings.portrait_image` directly [src:
`scripts/ui/views/level_end/states/end_view_state_score.lua:479-516`]. The
widget draws that identifier as an 86x108 texture pass [src:
`scripts/ui/ui_widgets_honduras.lua:13766-13869`]. The widget has no clipping
pass. `UIRenderer.script_draw_bitmap` checks `UIAtlasHelper`: atlas sprites use
`Gui.bitmap_uv`, while standalone identifiers fall through to `Gui.bitmap`
[src: `scripts/ui/ui_renderer.lua:60-118`]. Vanilla portraits are atlas sprites;
the #526 screenshot plus exact-alpha comparison proved DCP's standalone branch
was not equivalent. DCP therefore registers HUD/small cutouts in one private
atlas and keeps medium portraits standalone. Both normal paths use the proven
visible `gui:DIFFUSE_MAP`; the earlier standalone
`gui_gradient:DIFFUSE_MAP:MASKED` experiment rendered fully transparent.

The private atlas, standalone medium textures, and renderer materials are
registered through VMF's `custom_gui_textures` in `_data.lua` (a data API, not
a mod-owned hook). VMF's `inject_materials` reads the
`ui_renderer_creator` from `debug.traceback()` at frame 4 and matches it against
the basename of the `.lua` file that initiated the renderer-creation chain
[src: VMF `custom_textures.lua:191` per `DEVELOPMENT.md`]. Lua 5.1 tail-call
elimination strips the intermediate factory frames, so the creator seen is the
ENTRY-POINT file (`ingame_ui`, `hero_view`, `level_end_view_base`, ...), not the
inner `ingame_ui_settings` factory. Every entry-point that shows a portrait must
be listed or that surface crashes `Material 'X' not found in Gui` at draw time -
this is the same neighborhood as §23 (keep-only Gui material drawn mid-mission),
though `dcp`'s failure is a missing creator key, not a mission-residency gap.

## What the engine will NOT let us do (dead ends, already paid for)

Pulled from `DEVELOPMENT.md` "Dead ends" and `CLAUDE.md` - do not re-discover
these.

- **Per-widget content swap via the `UnitFrameUI.draw` hook only catches the
  HUD.** It misses hero-select (`content.portrait`), the ESC menu, the tab
  overlay, and end-of-round. The `career_settings` source swap is the only path
  that covers every surface from one write - which is why the draw hook is used as
  a readiness tick, not as the swap site.
- **`Material.set_texture()` / `Gui.create_material()` / `Gui.create()` are dead
  ends.** The Gui pipeline is separate: `Material.set_texture` no-ops silently,
  and `Gui.create_material` / `Gui.create` are nil in this VT2 build. Runtime
  texture replacement is not available; the swap must go through
  `career_settings`.
- **Hooking `UIRenderer.create` to detect material readiness never fires.** VMF
  destroys and recreates the renderer inside its own hook, so a user-mod
  `UIRenderer.create` hook never runs. A direct `Gui.material()` return-value
  probe across every discoverable renderer is the only reliable readiness check
  (`_check_portrait_materials_ready`, `:349`).
- **Multi-definition standalone `.material` files and user-owned
  UIAtlasHelper hooks are wrong.**
  Stingray creates exactly one Gui material per file, named after the FILENAME
  (extra `name = {}` blocks are ignored). VMF already owns the helper hooks and
  exposes `custom_gui_textures.atlases`; DCP uses that API instead of installing
  another hook. Do not register a HUD/small identifier as both standalone and
  atlas: VMF explicitly rejects the collision.
- **Issue 435 player scope.** The local source swap still writes the shared
  `career_settings` entry, but other-player HUD, Tab, and score consumers resolve
  at their per-player draw/build seams from synced cosmetics, falling back to
  vanilla rather than the local override. Live Player and score-record adapters
  consume one pure skin-first resolver; the closed-issue automatic telemetry was
  retired under #499. Secondary transient surfaces remain enumerated beside the
  hook implementation.

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if the dcp hook moves, the
swap target changes, or a cited vanilla line drifts after a game patch, edit the
affected row in the SAME commit. This doc complements, and must not duplicate,
`DEVELOPMENT.md` (asset pipeline + renderer-creator theory + dead ends) and
`CLAUDE.md` (workflow) - when the swap generalizes beyond Kruber Mercenary,
`DEVELOPMENT.md` is the primary and this doc's subsystem note is the follow-on
edit. The load-bearing citations (`unit_frame_ui.lua:326`,
`cosmetic_utils.lua:254`, `career_settings.lua` portrait fields) were verified
this pass. Line numbers are against the 2026-07-12 decompile - match crash logs by
function name, not line. Section shape (hook table -> subsystem notes -> dead
ends) matches `character_weapon_variants/ENGINE_SURFACE.md`. Reverse index:
`docs/engine/README.md` "Per-mod surface docs".
