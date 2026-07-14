# Simple UI integration audit (#314)

Status: phase 1 deployed in `gui_tweaker_dev` 0.2.246-dev; awaiting verification.

## Provenance and redistribution boundary

- Workshop item [Simple UI (Abandoned), 1389872347](https://steamcommunity.com/sharedfiles/filedetails/?id=1389872347) identifies grasmann as the author, version 2.1.2, sanctioned status approved, and last update 2019-10-31.
- The Workshop page links the public [Grasmann-Mods repository](https://github.com/Vermintide-Mod-Framework/Grasmann-Mods/tree/master/simple_ui). The repository contains the Simple UI source and resources but declares no GitHub license and has no LICENSE/COPYING file.
- Sanctioned status establishes game/mod-policy approval, not a software redistribution license. Until the author or rights holder supplies permission or a license, GUT must not copy the Simple UI implementation or its resource package. Runtime compatibility against its public object model and a clean implementation based on vanilla APIs remain available.

## Source findings

The audited 2.1.2 source is available locally at `misc-vermintide-mods/Simple UI (Abandoned)` and matches Workshop payload 1389872347.

- `simple_ui.lua:112-129` creates windows and registers them in `SimpleUI.windows.list`.
- `simple_ui.lua:1178-1188` writes cursor-derived drag coordinates directly to `window.position` with no screen clamp.
- `simple_ui.lua:1190-1224` enforces minimum resize dimensions but no maximum viewport boundary.
- `simple_ui.lua:2128-2150` always lays dropdown rows downward; `:2168-2175` expands hit bounds by every option, so a long or low-screen dropdown can extend below the screen.
- UI Tweaks' `buffs_manager.lua:31` draws preview icons at fixed `screen_width/screen_height` coordinates, while `:97-104` creates a movable Simple UI window. The icon draw never consumes `bm.main_window.position`, which explains why moving the window leaves the icons behind.
- GUT currently absorbs only UI Tweaks' data/hide/loading-screen phase (`hb_data.lua`, `hide_elements.lua`, `level_loading_screen.lua`). It does not load the upstream presets or buff-manager modules. The existing HUD Customizer owns vanilla HUD scenegraph nodes, not arbitrary Simple UI windows, so generic window containment is non-overlapping.

## Phased scope

### Phase 1 — recover and confine windows (implemented)

- Observe the installed Simple UI's public `windows.list` from GUT's existing update chain.
- Keep any window that fits wholly inside the current resolution.
- If a window is larger than the screen, keep its left edge and top title/drag edge reachable rather than shrinking consumer content unsafely.
- Mutate the existing position table in place so consumer references remain valid.
- No copied upstream code/assets, no external hook replacement, and no work when Simple UI is absent.

### Phase 2 — bounded dropdown layout

- Add a clean policy that selects downward or upward expansion from available space and limits visible rows.
- Confirm how Simple UI consumers expect `show_items_num` and scrolling to behave before modifying live option placement.
- Cover top/bottom placement, long option sets, UI scaling, and click bounds offline before runtime wiring.

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

## Phase-1 verification

1. Install and enable Simple UI plus a consumer such as stock UI Tweaks.
2. Drag each Simple UI window past all four edges. It must stop with the complete window visible when it fits.
3. Resize a window larger than the screen. Its left edge and top title/drag handle must remain reachable.
4. Change resolution/UI scale and reopen the window; it must be recovered into the new viewport.
5. Run `/gut_regression_test`; `issue314_simple_ui_window_confinement` must pass.
