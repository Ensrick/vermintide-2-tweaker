# Native loadout capacity (#231)

## Current result

GUT's modded-only native store is already capacity-agnostic and its separate chat
commands accept slots 1–30. The native hero-view pipeline is not yet safe to raise
to 30. The original pass added an automatic census rather than mutating the
global inventory schema before the UI and asset boundaries were ready. That
census has now been consumed and retired; the pure capacity policy and its host
tests remain as the implementation boundary.

Vanilla derives `InventorySettings.MAX_NUM_CUSTOM_LOADOUTS` from six custom rows
in `inventory_settings.lua`. The loadout-selection definitions then create one
physical widget per row at module-load time, with every button placed on one
horizontal strip. The window indexes those widgets directly by logical loadout
index in selection, context-menu, add, delete, bot, animation, and draw paths.
Appending 24 data rows alone would therefore create an off-screen strip and is
not a usable cutover.

Slots VII–XXX also have no stock `loadout_icon_7..30` atlas materials or
`custom_loadout_7..30_title` localization. Supplying names alone cannot make a
missing texture safe: the definition constructor asks `UIAtlasHelper` for atlas
settings while the window module loads.

## Implementable paging contract

The smallest safe final architecture is six reusable physical buttons mapped to
one logical page of six slots, for five pages total. Every direct
`self._loadout_button_widgets[logical_index]` access must first be routed through
that mapping, including selection frames, context menus, delete animations, bot
designation, and add behavior. Page controls must preserve keyboard/gamepad
navigation and automatically reveal the selected slot. Only after that owner is
covered should the modded-realm gate append rows 7–30 and raise the cap; official
and Versus paths must retain the original six-row table.

The asset choice remains explicit: either package VII–XXX materials through
`custom_gui_textures`, or make the reusable buttons text-only and generate Roman
numerals without requesting absent atlas textures. The latter avoids 24 new
materials but still requires the complete paging owner above.

## Retired census evidence

The former `/gut_loadout_capacity_probe` established six custom rows, a declared
cap of six, six instantiated widgets, and absent icon/title assets for slots
7–30. Repeating that automatic window-entry census cannot change the design
boundary and produced unbounded session logging, so #499 retired it. The
engine-free `_gut_loadout_capacity_policy.lua` tests retain the 30-slot target,
duplicate detection, sparse persisted extent, paging requirement, and direct
cutover conditions without loading a runtime probe.
