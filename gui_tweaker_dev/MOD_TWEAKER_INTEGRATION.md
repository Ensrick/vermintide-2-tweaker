# Mod Tweaker — integration intent (AUTHORITATIVE)

> **Read this before wiring ANY mod's options into the Mod Tweaker.** It exists because
> issue #339 (CRITICAL): Crosshair Kill Confirmation (#313) was wrongly added as a
> top-level TAB. The rules below are binding; a violation is a critical bug, not a style
> nit.

## The two-line rule

1. **A top-level Mod Tweaker TAB is ONLY for one of the author's OWN Tweaker-series mods**
   (the shared `AUTHOR_MOD_IDS` policy in `_mod_tweaker_disabled_sections.lua`): `gut`, `wt`, `ct`, `cim`, `gt`,
   `crt`, `cosmetics_tweaker`, `character_weapon_variants`, `enemy_tweaker`, `event_tweaker`,
   `mp`, `bt`, `dynamic_cosmetic_portraits` (+ their `_dev` ids). Each is a distinct mod the
   user ships; each earns one tab.
2. **A THIRD-PARTY mod we INTEGRATE (absorb / bridge / interoperate with) is NEVER a tab and
   NEVER a top-level collapsible.** Its options fold **into the appropriate existing gut
   category collapsible**, as rows (or a sub-`group`) within that category.

If you are about to add a non-author mod id to `AUTHOR_MOD_IDS`, STOP — that is the exact mistake
#339 corrects.

## How the Mod Tweaker is structured

The Mod Tweaker view (`_mod_tweaker_view.lua`) mirrors the vanilla VT2 options menu:

- **Top tab strip** — one tab per authored-mod policy entry (auto-discovered from VMF). Picking a tab
  shows that mod's options.
- **Within a tab** — the mod's options are organized into **category collapsibles** (native
  VMF `group` widgets with an expand/collapse arrow). This
  is the repo-wide standard: settings live in collapsible `group`s, never as a flat wall and
  never as extra tabs.

gut's own tab has categories like **Interface / HUD** (`gut_hide_hud_ui_group`), Gameplay,
etc. Integrated third-party options belong inside one of these.

## The correct precedent: UI Tweaks / HideBuffs (#312)

HideBuffs ("UI Tweaks") is deliberately **NOT** in `AUTHOR_MOD_IDS`. When the stock mod is
installed and enabled, GUT reads its **current live `VMF.options_widgets_data` tree** and folds
shallow copies of every group/value node inside the HUD group
(`gut_hide_hud_ui_group` > "UI Tweaks"). The shared
`_mod_tweaker_external_group.lua` planner rebases depths without mutating VMF-owned nodes;
both keep and mission presentations consume that one planner. This means a future UI Tweaks
group, checkbox, slider, dropdown, or keybind appears without adding it to a GUT allow-list.
The old authored HideBuffs subset is only a fail-closed fallback when the stock mod is absent
or its VMF tree is not ready. **This live-tree fold is the model every third-party integration
follows.** Re-adding HideBuffs to `AUTHOR_MOD_IDS` would resurrect the duplicate tab — don't.

**Sync to the stock mod (#312, `_bridge_uitweaks_to_stock`, marker `[UITWEAKS-BRIDGE-312]`).**
gut and the stock UI Tweaks (HideBuffs) mod persist those verbatim ids in **separate** VMF
namespaces (`gut_dev` vs `HideBuffs`), so the surfaced toggles must NOT read gut's own private
copies or they diverge from UI Tweaks' own VMF page (the exact bug the user reported). When
HideBuffs is installed **and enabled**, both Mod Tweaker twins route every live value node's
setting_id get/set to `get_mod("HideBuffs")` through the per-node `_owners` mechanism (the
same own-or-pin path Equipment/#208 and CKC/#339 use, and the drag-offset sync module already
uses for the four repositioned bars). Reads show HideBuffs' live value; edits commit as
`HB:set(id, v, true)`. `"HideBuffs"` is merged into the gut category's `_owner_mod_ids` so
Apply/dirty flush its buffer alongside gut's own and any CKC edits. GUT's ten per-tab profiles
explicitly exclude the `HideBuffs` owner: UI Tweaks retains its own profile authority and a
GUT profile switch cannot rewrite its settings. When HideBuffs is absent
the bridge is a no-op and gut's own copies drive its absorbed `hb/` fork as before (that fork
uses the repository-owned Penlight-free shim shipped under #281). **When integrating another
mod whose options gut mirrors 1:1, bridge to that
mod's live settings — never display a private copy.**

When HideBuffs is installed but disabled, keep the `UI Tweaks` group header in its normal
location, mark it read-only/grey, attach the `Disabled in VMF` hover explanation, and omit
its children. Do not route a staged owner buffer to the dormant object. Absence remains
different from disablement: when HideBuffs is not installed, gut's absorbed fallback rows
remain available.

## Crosshair Kill Confirmation (#313) — the required shape

CKC's options must appear **inside Interface / HUD**, editable in the Mod Tweaker's own menu,
following the UI Tweaks model:

- **Do NOT** whitelist `"Crosshair Kill Confirmation"` in `AUTHOR_MOD_IDS` (that is the current
  bug — it produces a top-level CKC tab).
- Surface CKC's options as rows / a sub-`group` under the HUD category. Because CKC is a live
  external mod, read/write the CKC mod's own settings through its `:set`/`:get` API.
- **Do not integrate CKC into vanilla Options.** No row replacement, checkbox conversion,
  gear, focus redirect, native-setting suppression, widget/material injection, or CKC-owned
  `OptionsView` hook is permitted (#528 user decision, 2026-07-14). CKC controls belong only
  to CKC's VMF page and this Mod Tweaker HUD fold.

## Decision test (apply every time)

```
Is this one of the author's own Tweaker-series mods (shipped by us, in the Tweaker family)?
  YES -> it may have its own top-level tab (add to AUTHOR_MOD_IDS).
  NO  -> it is a third-party integration:
         - fold its options into the appropriate EXISTING gut category collapsible
           (crosshair/HUD stuff -> Interface/HUD; etc.)
         - NEVER add it to AUTHOR_MOD_IDS
         - NEVER give it a top-level collapsible of its own
         - do not modify vanilla Options to provide a shortcut into the integration
```

## Mutually-exclusive option groups (#446)

Some settings can't be enabled together -- e.g. rival rework options for the same talent
(the issue's example: "Zealot THP Conversions" = None / On Ability Use / Devotion). Declare
them as a **mutually-exclusive group**: selecting one member in the Mod Tweaker turns the
others OFF. With radio presentation metadata, all-off is rendered as an explicit UI-only
`None [Default]` choice.

- **Members remain real VMF boolean/checkbox settings** in your own mod. The optional
  `{ control="radio", ... }` metadata changes only Mod Tweaker's presentation: gut replaces
  a complete same-parent cluster with one synthetic collapsible, `None [Default]`, and one
  bubble row per setting. Stock VMF and older gut versions retain ordinary checkboxes.
- Radio synthesis is deliberately same-mod and same-parent. Cross-mod, incomplete, or
  structurally scattered groups keep their checkbox rows while retaining exclusivity.
- **Declare it from your own mod** via the gut public API (data-driven -- gut needs no code
  change per group):

  ```lua
  local gut = get_mod("gut_dev")   -- or "gut" against the stable item
  if gut and gut.mod_tweaker and gut.mod_tweaker.register_exclusive_group then
      gut.mod_tweaker:register_exclusive_group("crt_zealot_thp", {
          { mod = "crt", setting = "zealot_thp_on_ability" },
          { mod = "crt", setting = "zealot_thp_devotion" },
      }, {
          control = "radio",
          label = "zealot_thp_conversions_group", -- owner-mod localization key
          none_label = "none_default",            -- UI-only; writes all members false
      })
  end
  ```

- **Enforcement** happens only inside the Mod Tweaker's own menu (the radio/checkbox handler
  stages siblings OFF and rebuilds the rows). Editing the same setting in VMF's stock options
  menu is NOT swept -- register the group above and, if you need hard exclusivity everywhere,
  also guard it in your own `on_setting_changed`.
- **Same-mod members commit together** on that tab's APPLY. Cross-mod members buffer under
  each owner mod's tab, so a cross-mod sibling commits when ITS tab is applied.

Resolve group ids from gut with `:get_exclusive_group_id(mod_id, setting_id)`,
`:get_exclusive_members(group_id)`, and `:get_exclusive_presentation(group_id)`. Registry +
API live in `_mod_tweaker_settings.lua` / `_mod_tweaker.lua`; the fail-closed layout planner is
`_mod_tweaker_exclusive_layout.lua`; the sweep is `ModTweakerView:_enforce_exclusive`.

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

The synthetic **Equipment** tab is a multi-owner transaction, not one giant
GUI-owned callback. Its four current owner families -- Cosmetics, CIM, Weapon
Tweaker, and CWV -- must each implement the opt-in callback in every selectable
stable/dev alias. The source audit for issue #1002 shows that leaving Weapon
Tweaker on the legacy path makes every `unlock_*` default repeat the complete
availability and career-action rebuild. The required bound is therefore:

- persist every changed value, grouped by owner;
- invoke at most one owner completion callback per non-empty owner buffer;
- retain the exact owner buffer and suppress profile capture if a silent write
  or completion callback fails, so Apply can retry rather than certify a
  partial state;
- reconcile select-all/master controls before the owner's one final apply;
- when a DEFAULT/profile snapshot contains both a master and all of its
  children, preserve the committed child values and derive the master instead
  of cascading the master over mixed defaults.

Do not make batching implicit for arbitrary future owners. Adding another mod
to `EQUIPMENT_ROLES` requires its explicit `on_settings_batch_changed(ids)`
adapter and an offline assertion that callback/application count is bounded by
owner count, not setting count.

## Per-tab search expansion transaction (#497 / #559)

The fixed search bar filters only the current tab. Matching groups and the ancestors required to
show a nested match are rendered open, but search presentation never writes persistent collapsible
state. The first non-empty query snapshots that tab's open groups.

- Changing a result does not dismiss or alter the filtered result set. The view remembers the most
  recently staged setting while checkbox, dropdown, keybind, numeric, and slider interactions proceed.
- Escape, a neutral click outside the search/results, tab/profile switch, and menu exit finish the
  transaction. With auto-collapse enabled, only the last changed setting's ancestor chain remains
  open; when nothing changed, the first direct result supplies the fallback chain. A top-level result
  has no ancestors. With auto-collapse disabled, the snapshot remains open and the retained chain is
  added.
- Refocusing and editing the query resets the last-changed choice because the result set changed.
  Backspacing to empty uses the same finish behavior as explicit dismissal.

## Per-tab settings profiles (#561)

Both Mod Tweaker presentations expose ten numbered profiles in the lower-left.
The active slot is scoped to the visible tab and persisted across restarts. Slot
1 adopts the live pre-profile settings on first use; unused slots start from the
tab's declared defaults. Applying an edit captures the resulting live values in
the active slot. A profile-button click auto-applies pending edits to the old
slot before restoring the new slot. If any owner transaction remains pending,
the switch aborts before profile capture or active-slot mutation, so staged or
partially committed values cannot leak across profiles.

Storage is partitioned as `mt_profile::<tab>::<slot>` maps and one
`mt_profile_active::<tab>` scalar. Never replace this with a monolithic profile
tree: VMF deep-clones the complete value passed to `mod:set`. Merged tabs store
flat length-prefixed owner/setting keys so each stored value retains its owner.
Restoration stages through the ordinary owner buffers and calls the #560 bounded
transaction path. Keybinds are excluded because they are device-global and need
VMF's separate binding-registration lifecycle.

## Settings-tree ordering (#557)

Mod Tweaker orders each unordered sibling list as two alphabetical partitions:
collapsible `group` nodes first, then loose settings. Labels are the localized
display strings users see. The implementation rebuilds the tree from VMF's flat
node/depth arrays before sorting, so descendants always travel with their parent.

Authored organization is fail-closed. A sibling list containing an authored
`header`, `mod_tweaker_preserve_order = true`, `mod_tweaker_order`,
`mod_tweaker_before`, `mod_tweaker_after`, `depends_on`, or `dependency` retains
its original order. VMF's generated, non-rendered per-mod header stays anchored
but does not block sorting of the actual rows. Use the namespaced fields for new
Tweaker integrations; dependency fields are recognized for compatibility. The
synthetic Equipment tab opts out because its sections have a deliberate sequence.

## Regression guard

`_mod_tweaker_disabled_sections.lua` / the gut regression suite must assert: no third-party
(non-author) mod id appears in `AUTHOR_MOD_IDS`, and CKC's options resolve under the HUD
category. See #339. The
`mod_tweaker_exclusive_group_api` check (#446) asserts the exclusive-group registry + the
view's `_enforce_exclusive` sweep stay wired.
