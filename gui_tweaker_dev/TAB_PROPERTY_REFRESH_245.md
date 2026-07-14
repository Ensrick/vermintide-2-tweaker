# Held-Tab weapon property refresh (#245)

## Source boundary

The v2 player-list UI renders weapon tooltips from
`Managers.player:player_loadouts()`. Those rows are detached presentation copies
created by `PlayerManager.rpc_sync_loadout_slot`; they contain item key, rarity,
power, properties, and traits, but no backend instance id. The UI even reads the
live inventory extension into a local `equipment` variable, then never uses it.
Consequently, changing an equipped instance's properties in place leaves the Tab
copy stale until another equipment synchronization occurs.

## Repair

While the v2 Tab view is active, GUT checks at most four times per second. For the
local player's melee and ranged slots it follows the live inventory extension's
exact backend id, fetches that instance from the item interface, verifies the item
identity still matches the detached Tab row, and copies properties only when a
deterministic fingerprint changed.

This updates only the existing presentation cache. It does not re-equip a weapon,
reapply buffs, write backend data, poll while Tab is closed, or add RPC traffic.
Remote players continue to use the properties received through vanilla's loadout
sync. Diagnostic output is capped to sixteen actual changes per process.

## Solo verification

Equip a weapon, note its held-Tab tooltip properties, change that exact equipped
instance's properties through CIM, then hold Tab and hover the same weapon again.
The new properties should appear within 0.25 seconds without swapping weapons.
Attach the bounded `[gut:245]` line and run `/gut_regression_test`; confirm
`issue245_tab_weapon_property_refresh` passes.
