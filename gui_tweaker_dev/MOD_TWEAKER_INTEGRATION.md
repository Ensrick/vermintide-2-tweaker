# Mod Tweaker — integration intent (AUTHORITATIVE)

> **Read this before wiring ANY mod's options into the Mod Tweaker.** It exists because
> issue #339 (CRITICAL): Crosshair Kill Confirmation (#313) was wrongly added as a
> top-level TAB. The rules below are binding; a violation is a critical bug, not a style
> nit.

## The two-line rule

1. **A top-level Mod Tweaker TAB is ONLY for one of the author's OWN Tweaker-series mods**
   (the `_MY_MODS` whitelist in `_mod_tweaker_view.lua`): `gut`, `wt`, `ct`, `cim`, `gt`,
   `crt`, `cosmetics_tweaker`, `character_weapon_variants`, `enemy_tweaker`, `event_tweaker`,
   `mp`, `bt`, `dynamic_cosmetic_portraits` (+ their `_dev` ids). Each is a distinct mod the
   user ships; each earns one tab.
2. **A THIRD-PARTY mod we INTEGRATE (absorb / bridge / interoperate with) is NEVER a tab and
   NEVER a top-level collapsible.** Its options fold **into the appropriate existing gut
   category collapsible**, as rows (or a sub-`group`) within that category.

If you are about to add a non-author mod id to `_MY_MODS`, STOP — that is the exact mistake
#339 corrects.

## How the Mod Tweaker is structured

The Mod Tweaker view (`_mod_tweaker_view.lua`) mirrors the vanilla VT2 options menu:

- **Top tab strip** — one tab per `_MY_MODS` entry (auto-discovered from VMF). Picking a tab
  shows that mod's options.
- **Within a tab** — the mod's options are organized into **category collapsibles** (native
  VMF `group` widgets with an expand/collapse arrow). This
  is the repo-wide standard: settings live in collapsible `group`s, never as a flat wall and
  never as extra tabs.

gut's own tab has categories like **Interface / HUD** (`gut_hide_hud_ui_group`), Gameplay,
etc. Integrated third-party options belong inside one of these.

## The correct precedent: UI Tweaks / HideBuffs (#312)

HideBuffs ("UI Tweaks") is deliberately **NOT** in `_MY_MODS`
(`_mod_tweaker_view.lua:162-164`). Its features were absorbed into gut's own data tree under
the HUD group (`gut_hide_hud_ui_group`) — the settings render as ordinary gut options within
that collapsible and drive the behavior directly. **This is the model every third-party
integration follows.** Re-adding HideBuffs to `_MY_MODS` would resurrect the duplicate tab —
don't.

## Crosshair Kill Confirmation (#313) — the required shape

CKC's options must appear **inside Interface / HUD**, editable in the Mod Tweaker's own menu,
following the UI Tweaks model:

- **Do NOT** whitelist `"Crosshair Kill Confirmation"` in `_MY_MODS` (that is the current
  bug — it produces a top-level CKC tab).
- Surface CKC's options as rows / a sub-`group` under the HUD category. Because CKC is a live
  external mod, drive it live via VMF (`get_mod("VMF").mod_state_changed`, and the CKC mod's
  own `:set`/`:get`) — the same live-bridge `_gut_ckc_bridge.lua` already uses for the
  vanilla-menu takeover.
- **The vanilla-Options gear** (`_gut_ckc_bridge.lua`) that opens the Mod Tweaker must focus
  the **HUD category**, not a CKC tab. `mod._gut_mt_focus_request` must carry a
  category/anchor target, not the mod name as a tab id.

## Decision test (apply every time)

```
Is this one of the author's own Tweaker-series mods (shipped by us, in the Tweaker family)?
  YES -> it may have its own top-level tab (add to _MY_MODS).
  NO  -> it is a third-party integration:
         - fold its options into the appropriate EXISTING gut category collapsible
           (crosshair/HUD stuff -> Interface/HUD; etc.)
         - NEVER add it to _MY_MODS
         - NEVER give it a top-level collapsible of its own
         - any "open in Mod Tweaker" bridge focuses the CATEGORY, not a tab
```

## Regression guard

`_mod_tweaker_view.lua` / the gut regression suite must assert: no third-party (non-author)
mod id appears in `_MY_MODS`, and CKC's options resolve under the HUD category. See #339.
