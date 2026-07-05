# Weapons of Chaos — Changelog

## 0.1.5-dev (2026-07-04) — Localization: applied dev status-tag doctrine (#301). Tagged the 1 option-title loc entry (Enable Blightreaper) with a dev status prefix: 1 [untested] (brand-new mod, placeholder base-sword mesh, unverified in-game). No open issues map to WOC. Tooltips, item name/description, and mod description left untagged per doctrine.

## 0.1.4-dev (2026-07-01) — Localization fixes: the Enable Blightreaper checkbox tooltip was double-localized (rendered wrapped in angle brackets); converted its widget field from an eager mod:localize() call to the raw loc key so VMF localizes it once. Rewrote every option description and tooltip (mod description, Blightreaper item description, Enable Blightreaper tooltip) into plain player-facing English, ASCII-only (dropped the non-ASCII spelling of Bogenhafen).

## 0.1.3-dev (2026-06-29) — Fixed keep-entry crash: the Bögenhafen trophy diorama prop (units/props/inn/hub_trophy/hub_trophy_bogenhafen) is NOT runtime-loadable (no standalone .package; absent from the boot-loaded bogenhafen DLC + base keep `inn` bundles), so force-loading its unit path hard-crashed on keep entry. Interim held mesh reverted to the base Empire 1H sword (HELD_UNIT, crash-free); swap to an extracted Blightreaper .unit once a real model is authored. Research + post-mortem in DEVELOPMENT.md.

## 0.1.2-dev (2026-06-28) — Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.1.1-dev (2026-06-28) — Initial scaffolding: Blightreaper (Bögenhafen trophy diorama prop as 1H sword), equippable by all 20 careers, MoreItemsLibrary registration, 3P-unit derivation fix, inventory-preview fallback.
