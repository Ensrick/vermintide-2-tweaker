# Simple UI integration audit (#314)

Status: phase 1 deployed in `gui_tweaker_dev` 0.2.246-dev; phase 2 implemented in
0.2.349-dev. Phases 3-4 remain; phase 5 stays out of scope pending a license.

## Provenance and redistribution boundary

- Workshop item [Simple UI (Abandoned), 1389872347](https://steamcommunity.com/sharedfiles/filedetails/?id=1389872347) identifies grasmann as the author, version 2.1.2, sanctioned status approved, and last update 2019-10-31.
- The Workshop page links the public [Grasmann-Mods repository](https://github.com/Vermintide-Mod-Framework/Grasmann-Mods/tree/master/simple_ui). The repository contains the Simple UI source and resources but declares no GitHub license and has no LICENSE/COPYING file.
- Sanctioned status establishes game/mod-policy approval, not a software redistribution license. Until the author or rights holder supplies permission or a license, GUT must not copy the Simple UI implementation or its resource package. Runtime compatibility against its public object model and a clean implementation based on vanilla APIs remain available.

## Source findings

The audited 2.1.2 source is available locally at `misc-vermintide-mods/Simple UI (Abandoned)` and matches Workshop payload 1389872347.

- `simple_ui.lua:112-129` creates windows and registers them in `SimpleUI.windows.list`.
- `simple_ui.lua:1178-1188` writes cursor-derived drag coordinates directly to `window.position` with no screen clamp.
- `simple_ui.lua:1190-1224` enforces minimum resize dimensions but no maximum viewport boundary.
- `simple_ui.lua:862-884` and `:1407-1432` copy widget prototype functions into each widget instance, so every per-frame call goes through instance fields.
- `simple_ui.lua:1433-1436`: a widget's `update` calls its public `before_update` first, then (unless `disabled`) runs the hover test against `extended_bounds`; `render_background` (`:1527-1531`) draws from the same box.
- `simple_ui.lua:2128-2150` always lays dropdown rows downward by each option's `index`; `:2168-2175` expands hit bounds by every option, so a long or low-screen dropdown can extend below the screen. `:2100-2126` routes click/release to whichever option's `extended_bounds` contains the cursor. `show_items_num` (`:840`) and the theme's `draw_items_num` are stored but never read.
- UI Tweaks' `buffs_manager.lua:31` draws preview icons at fixed `screen_width/screen_height` coordinates, while `:97-104` creates a movable Simple UI window. The icon draw never consumes `bm.main_window.position`, which explains why moving the window leaves the icons behind.
- GUT currently absorbs only UI Tweaks' data/hide/loading-screen phase (`hb_data.lua`, `hide_elements.lua`, `level_loading_screen.lua`). It does not load the upstream presets or buff-manager modules. The existing HUD Customizer owns vanilla HUD scenegraph nodes, not arbitrary Simple UI windows, so generic window containment is non-overlapping.

## Phased scope

### Phase 1 — recover and confine windows (implemented)

- Observe the installed Simple UI's public `windows.list` from GUT's existing update chain.
- Keep any window that fits wholly inside the current resolution.
- If a window is larger than the screen, keep its left edge and top title/drag edge reachable rather than shrinking consumer content unsafely.
- Mutate the existing position table in place so consumer references remain valid.
- No copied upstream code/assets, no external hook replacement, and no work when Simple UI is absent.

### Phase 2 — bounded dropdown layout (implemented, 0.2.349-dev)

- Pure `dropdown_layout` policy: open downward when the whole list fits below, upward when it fits above, otherwise on the roomier side with only the rows that fit. Rows keep ascending order from top to bottom; an upward list ends on the control's top edge. The row gap is `2 * UIResolutionScale()` like upstream.
- A long list scrolls with the mouse wheel while the cursor is over the open list and reveals the selected option each time it opens.
- `_gut_simple_ui_dropdowns.lua` (loaded from the compat tail) wraps each live dropdown instance's own `update` (layout, scroll, wheel), replaces only that instance's `extended_bounds` with the fitted hit box, and chains each option's public `before_update` to place its row or hide, disable and park a scrolled-out row off-screen. Hit box and rendered rows come from one layout, so they cannot diverge; parked rows are restored the moment the list closes.
- Upstream never read `show_items_num`, so no consumer contract depends on it; the visible-row count comes from screen space alone.
- **Fit Simple UI Dropdowns** (default on) installs nothing when off.

### Phase 3 — UI Tweaks buff-manager coupling

- When the standalone UI Tweaks owns its buff manager, derive preview-icon positions from the live `bm.main_window.position` rather than fixed screen corners.
- If GUT later absorbs the buff manager, implement the same behavior cleanly in GUT rather than copying the unlicensed module.
- Verify dragging, minimize/maximize, resolution changes, and icon click targets together.

### Phase 4 — native presentation and feedback

- Inventory the vanilla border, button, hover, pressed, and sound-event contracts from the VT2 source before selecting only materials resident in the top-ingame GUI.
- Build the theme as a GUT-owned adapter. Do not redistribute Simple UI's package.
- Verify keyboard/mouse/gamepad input, hover/press states, and audio rate limits.

### Phase 5 — optional source absorption

Only proceed if an explicit compatible license or author permission is recorded in-repo. Preserve attribution, license text, upstream commit/version, a modification ledger, and a clean ownership boundary with GUT lifecycle callbacks.

## Verification (phases 1-2)

1. Install and enable Simple UI plus a consumer such as stock UI Tweaks.
2. Drag each Simple UI window past all four edges. It must stop with the complete window visible when it fits.
3. Resize a window larger than the screen. Its left edge and top title/drag handle must remain reachable.
4. Change resolution/UI scale and reopen the window; it must be recovered into the new viewport.
5. Open a dropdown near the bottom of the screen and one with more options than fit. The first opens upward; the second shows only the rows that fit, scrolls with the mouse wheel over the list, reopens on the selected option, and every visible row selects on click. Turn **Fit Simple UI Dropdowns** off to compare with upstream placement.
6. Run `/gut_regression_test`; `issue314_simple_ui_window_confinement` and `issue314_simple_ui_phase2` must pass.
