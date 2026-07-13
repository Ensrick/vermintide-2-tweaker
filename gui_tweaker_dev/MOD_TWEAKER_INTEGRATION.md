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

HideBuffs ("UI Tweaks") is deliberately **NOT** in `_MY_MODS`. Its options render as ordinary
gut checkboxes inside the HUD group (`gut_hide_hud_ui_group` > "UI Tweaks"), keeping HideBuffs'
setting_ids verbatim. **This is the model every third-party integration follows.** Re-adding
HideBuffs to `_MY_MODS` would resurrect the duplicate tab — don't.

**Sync to the stock mod (#312, `_bridge_uitweaks_to_stock`, marker `[UITWEAKS-BRIDGE-312]`).**
gut and the stock UI Tweaks (HideBuffs) mod persist those verbatim ids in **separate** VMF
namespaces (`gut_dev` vs `HideBuffs`), so the surfaced toggles must NOT read gut's own private
copies or they diverge from UI Tweaks' own VMF page (the exact bug the user reported). When
HideBuffs is installed **and enabled**, both Mod Tweaker twins route every overlapping checkbox
setting_id's get/set to `get_mod("HideBuffs")` through the per-node `_owners` mechanism (the
same own-or-pin path Equipment/#208 and CKC/#339 use, and the drag-offset sync module already
uses for the four repositioned bars). Reads show HideBuffs' live value; edits commit as
`HB:set(id, v, true)`. `"HideBuffs"` is merged into the gut category's `_owner_mod_ids` so
Apply/dirty flush its buffer alongside gut's own and any CKC edits. When HideBuffs is absent
the bridge is a no-op and gut's own copies drive its absorbed `hb/` fork as before (that fork
also aborts at load on a missing Penlight dep, #281, so the stock mod is the real provider on
most setups). **When integrating another mod whose options gut mirrors 1:1, bridge to that
mod's live settings — never display a private copy.**

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

## Mutually-exclusive option groups (#446)

Some settings can't be enabled together -- e.g. rival rework options for the same talent
(the issue's example: "Zealot THP Conversions" = None / On Ability Use / Devotion). Declare
them as a **mutually-exclusive group**: switching one member ON in the Mod Tweaker turns the
others OFF (a radio group over ordinary checkboxes; all-off is a valid "None" state).

- **Members are REAL VMF boolean/checkbox settings** in your own mod (or across mods). You do
  NOT invent a new widget type -- you keep normal `checkbox` widgets and register the
  exclusivity separately. For the collapsible look the issue mock-up shows, wrap the members
  in a native VMF `group` widget in your `_data.lua`; gut renders the group and enforces the
  exclusivity. No custom widget, no `_MY_MODS` change.
- **Declare it from your own mod** via the gut public API (data-driven -- gut needs no code
  change per group):

  ```lua
  local gut = get_mod("gut_dev")   -- or "gut" against the stable item
  if gut and gut.mod_tweaker and gut.mod_tweaker.register_exclusive_group then
      gut.mod_tweaker:register_exclusive_group("crt_zealot_thp", {
          { mod = "crt", setting = "zealot_thp_none" },      -- None [Default]
          { mod = "crt", setting = "zealot_thp_on_ability" },
          { mod = "crt", setting = "zealot_thp_devotion" },
      })
  end
  ```

- **Enforcement** happens only inside the Mod Tweaker's own menu (the checkbox toggle handler
  stages siblings OFF and rebuilds the rows). Editing the same setting in VMF's stock options
  menu is NOT swept -- register the group above and, if you need hard exclusivity everywhere,
  also guard it in your own `on_setting_changed`.
- **Same-mod members commit together** on that tab's APPLY. Cross-mod members buffer under
  each owner mod's tab, so a cross-mod sibling commits when ITS tab is applied.

Resolve group ids from gut with `:get_exclusive_group_id(mod_id, setting_id)` /
`:get_exclusive_members(group_id)`. Registry + API live in `_mod_tweaker_settings.lua` /
`_mod_tweaker.lua`; the sweep is `ModTweakerView:_enforce_exclusive` in `_mod_tweaker_view.lua`.

## Filtered / searchable dropdowns (#505)

A `dropdown` with many options (ct's ~40+ CW mission list is the motivating case) is painful to
scroll. When such a dropdown is opened in the Mod Tweaker, the popup now offers two filter axes:

1. **Type-to-filter (automatic).** Any dropdown with **8 or more options** shows a search line at the
   top of the open popup; typing narrows the list live (case-insensitive substring match on each
   option's label). This needs **no registration** -- it is on for every long dropdown.
2. **Category chips (opt-in).** Declare named categories for a specific dropdown and the popup adds a
   chip row (plus an implicit **All** chip). Clicking a chip filters the options to that category. The
   two axes compose (chip AND search term).

Plain dropdowns (< 8 options and no categories) are unchanged -- no search line, no chips.

- **Declare categories from your own mod** via the gut public API (data-driven -- gut needs no code
  change per dropdown):

  ```lua
  local gut = get_mod("gut_dev")   -- or "gut" against the stable item
  if gut and gut.mod_tweaker and gut.mod_tweaker.register_dropdown_categories then
      gut.mod_tweaker:register_dropdown_categories("<your_mod_id>", "<dropdown_setting_id>", {
          -- match = a FUNCTION called with (option_value, option_text) -> boolean:
          { label = "Travel",    match = function(value, text) return is_travel(value) end },
          -- match = a KEY-LIST tested against the option VALUE (membership):
          { label = "Signature", match = { "sig_gorge", "sig_volcano", "sig_crag" } },
      })
  end
  ```

- **Members reference the REAL dropdown** by its `setting_id` in your own `_data.lua`; you do NOT
  invent a widget type or change the dropdown. The `mod_id` is your **registered** VMF id (e.g. `ct`
  vs `ct_dev`), the same id the Mod Tweaker tab resolves against -- register under whichever stream
  you ship.
- **`match` gets the option `value`, not its display label.** If your options carry index values
  (`value = i`) rather than keys, resolve the key inside the function (`local key = MY_LIST[value]`).
  The key-list form tests the option `value` directly, so use it only when the values ARE the keys.
- **Re-registering the same (mod_id, setting_id) REPLACES** the category list, so an author reload
  re-declares cleanly. Reverse lookup: `gut.mod_tweaker:get_dropdown_categories(mod_id, setting_id)`.
- **Filtering is Mod-Tweaker-menu-only** and never changes the stored value -- it only narrows what
  the open popup shows. Selecting an option commits exactly as before.

Registry + API live in `_mod_tweaker_settings.lua` / `_mod_tweaker.lua`; the popup header + filter
path are in `_mod_tweaker_definitions.lua` (`create_dropdown_list`'s optional `header`) and
`_mod_tweaker_view.lua` (`_recompute_dd_visible` / `_dd_chips` / `_refresh_dropdown_list` /
`_handle_dropdown_input`). The `mod_tweaker_dropdown_filter_api` check (#505) asserts the registry +
API + view filter methods + the header-capable factory stay wired.

## Bulk setting transaction contract

Apply and DEFAULT may commit hundreds of settings from one tab. VMF's
`VMFMod:set(id, value, notify)` persists/clones the value and synchronously
dispatches `on_setting_changed` when `notify` is true (VMF
`modules/core/settings.lua:27-40`, `modules/core/events.lua:44-48`). A mod whose
callback performs expensive whole-mod recomputation can opt into a bounded commit:

```lua
mod.on_settings_batch_changed = function(setting_ids)
    -- All values are already persisted. Recompute once from current settings.
end
```

Both Mod Tweaker view twins then write that owner's values with `notify=false`
and invoke the callback once with a sorted array of changed setting ids. This is
strictly opt-in: owners without the callback retain per-setting VMF notifications,
because a generic sentinel would break callbacks that branch or clamp by id.
The implementation lives in `_mod_tweaker_transaction.lua`; issue #560 is the
Enemy Tweaker crash precedent. Future profiles/imports must reuse this transaction
instead of inventing another bulk-write loop.

## Per-tab search expansion transaction (#497 / #559)

The fixed search bar filters only the current tab. Matching groups and the ancestors required to
show a nested match are rendered open, but search presentation never writes persistent collapsible
state. The first non-empty query snapshots that tab's open groups.

- Clear, Escape, a neutral click outside the search/results, tab switch, and menu exit cancel the
  transaction and restore the exact snapshot. They never choose the first/top result implicitly.
- Clicking a result commits navigation and then performs the original control action. With
  auto-collapse enabled, only the result's ancestor group chain remains open; a top-level result has
  no ancestors. With auto-collapse disabled, the snapshot remains open and required ancestors are
  added.
- Dropdown, keybind capture, numeric editing, and slider drag keep their clicked row alive until the
  modal interaction completes. The normal list rebuild then blocks the old shared-node release latch
  until a fresh click.

## Per-tab settings profiles (#561)

Both Mod Tweaker presentations expose ten numbered profiles in the lower-left.
The active slot is scoped to the visible tab and persisted across restarts. Slot
1 adopts the live pre-profile settings on first use; unused slots start from the
tab's declared defaults. Applying an edit captures the resulting live values in
the active slot. A profile-button click auto-applies pending edits to the old
slot before restoring the new slot, so staged values cannot leak across profiles.

Storage is partitioned as `mt_profile::<tab>::<slot>` maps and one
`mt_profile_active::<tab>` scalar. Never replace this with a monolithic profile
tree: VMF deep-clones the complete value passed to `mod:set`. Merged tabs store
flat length-prefixed owner/setting keys so each stored value retains its owner.
Restoration stages through the ordinary owner buffers and calls the #560 bounded
transaction path. Keybinds are excluded because they are device-global and need
VMF's separate binding-registration lifecycle.

## Regression guard

`_mod_tweaker_view.lua` / the gut regression suite must assert: no third-party (non-author)
mod id appears in `_MY_MODS`, and CKC's options resolve under the HUD category. See #339. The
`mod_tweaker_exclusive_group_api` check (#446) asserts the exclusive-group registry + the
view's `_enforce_exclusive` sweep stay wired.
