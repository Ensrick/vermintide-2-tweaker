# GUI Tweaker (gut) — Tracked Status

Canonical running list of everything requested for the gut Mod Tweaker / GUI work, with honest status. Updated every time an item moves. If it's not here, it's at risk of being forgotten — so it goes here.

Legend: [x] done · [~] in progress · [ ] TODO · [-] blocked/parked

---

## Active bugs (top priority)

- [x] **`<>` on the ESC "Mod Tweaker" entry — ROOT CAUSE FOUND + FIXED (v0.2.51).** The modern hero menu (`hero_window_ingame_view.lua:473`) does `text_field = display_name_func() or display_name` then LOCALIZES `text_field`. Our button had a `display_name_func` returning the already-resolved string `"Mod Tweaker"`, which got re-localized into `<Mod Tweaker>`. (The legacy ESC button used the key directly, so it was fine — that's why the probe showed it resolving.) Removed the func; the key path now resolves in both menus. _Verify on relaunch._
- ⬜ **Exiting the Mod Tweaker shows the deprecated/legacy menu.** This was "fixed" in v0.2.46 by returning to `hero_view`, but that crashed with Loremaster's Armoury (VMF re-injects LA's atlas into the recreated renderer), so v0.2.48 **reverted to `ingame_menu`** → the legacy look is back. **Proper fix:** make the Mod Tweaker a **HeroView sub-state** (like `_ba_compendium_state`) so it never leaves/recreates hero_view — kills both the crash and the legacy look. Not started. This is the real next big task.

## Mod Tweaker native-parity rework (make it look/behave like the game's settings menu)
From the multi-agent design (workflow wf_f82a670a). NOT STARTED beyond the column split. Phased:

- ⬜ **Phase 1 — per-row scenegraph nodes.** Every row currently shares one `{1,1}` node; that's the root cause of the dead slider drag + cosmetic scrollbar. Give each row its own node. (Unblocks Phase 2.)
- ⬜ **Phase 2 — working slider drag (thumb follows cursor) + scrollbar that scales & drags.** Depends on Phase 1.
- ⬜ **Phase 3 — cosmetic parity:** dividers between settings · two-column with the current value shown on the right · native font + colors · shift tabs right so they clear the gear icon · native spacing · nested groups visually distinct (leading indent + different text color).
- ⬜ **Phase 4 — hover highlight + hover/select sounds** on rows and tabs.
- ⬜ **Phase 5 — On/Off switches instead of checkboxes · type-a-number boxes (like VMF) · mouseover tooltip descriptions.**

## Done (this session)
- ✅ **NumericUI ability cooldown shows real-time reduced seconds** (v0.2.55) — VT2 CDR speeds up the countdown; gut divides NumericUI's cooldown read by the `cooldown_regen` multiplier (only during NumericUI's display computation) so it ticks at 1/sec and shows the accurate reduced cooldown. Game logic/AI untouched.
- ✅ **Loremaster's Armoury hero-view atlas crash guarded** (v0.2.53) — gut pins LA's package so its atlas can't be unloaded out from under the hero-view HDR renderer (VMF injection → engine C-fatal). Not a gut bug, but fixed from our side with LA authors' permission. _Verify on relaunch: log shows `[gut] pinned Loremaster's Armoury atlas package`._
- ✅ **Captions no longer repositioned at default settings** (v0.2.52) — the HideBuffs subtitle-reposition hook was clobbering vanilla caption position with {0,0} every frame; now bails unless a non-zero offset is set.
- ✅ Collapsible group headers (default collapsed).
- ✅ Legacy ESC-button `<>` → "Mod Tweaker" (via `append_backend_localizations`).
- ✅ Slider value snaps like VMF (re-read after commit reflects mod-side snapping, e.g. ct's 25s).
- ✅ Two-column split started (label left @ TRACK_X, control right) — needs Phase 3 polish (value-on-right, dividers).
- ✅ Click sound on toggles.
- ✅ Hide UI migrated gt → gut (`/hud`), bugs fixed, + outline-disable & first-person-arms hide from the original mod.
- ✅ Temporal Fix baked in at -48, always on (toggle + slider removed).
- ✅ Exit-crash with Loremaster's Armoury — stopped (reverted exit routing).

---

_Maintained by Claude. Mirror the top items as GitHub issues; this file is the detailed index._
