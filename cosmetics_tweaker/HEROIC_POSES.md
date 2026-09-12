# Heroic Weapon Poses (#485)

## Vanilla path

Vanilla parses the backend `unlocked_weapon_poses` read-only value into a table keyed by each pose item's `parent` (`playfab_mirror_base.lua:227-268`). `SocialWheelUI._gather_weapon_poses_by_parent_item` then reads only that backend-owned parent bucket and resolves each backend id (`social_wheel_ui.lua:1075-1096`).

The wheel already owns the safe presentation path:

- it normalizes Versus weapon keys and loads `resource_packages/pose_packages/<weapon>` asynchronously (`social_wheel_ui.lua:840-904`);
- it creates the exact parent's pose and glow icons (`:974-1015`);
- it executes the authored animation event as `PingTypes.LOCAL_ONLY` (`:1016-1034`).

The item catalog itself is local shipped data. Valid rows have `item_type="weapon_pose"`, a weapon `parent`, `pose_index`, and `data.anim_event` (`item_master_list_weapon_poses.lua`). Therefore Cosmetics can expose already-authored poses without granting official ownership or inventing an RPC.

## Implemented boundary

With `cos_unlock_weapon_poses` enabled in the modded realm, `_cos_weapon_poses.lua` replaces only the gather result with exact-parent rows from the local `ItemMasterList`. Wrapper records point at the original immutable item data. The backend mirror, official entitlement table, equipped pose-skin table, and authored catalog remain untouched.

The option is deliberately inactive in the official realm. Toggling it changes the wheel's dirty state so the current item rebuilds once; no polling or per-frame catalog scan is added.

## Deferred fallback

Some modded or unusual weapon parents may have no authored pose rows or pose icon package. Reusing a random weapon's entries can combine the wrong animation vocabulary, icon paths, or package lifecycle. Those parents currently retain vanilla behavior. A donor fallback should ship only after the capture proves a compatible weapon family and package for each missing parent.

The parent key is the wielded item key with a leading `vs_` removed; for a magic-rarity item it is instead the raw key with its `_magic_0N` suffix removed (`social_wheel_ui.lua:862-866`). Vanilla calls the gather from `_is_dirty` as well as from the page build (`social_wheel_ui.lua:907-908,977`), so the capture must stay deduplicated.

## Capture bound

`_cos_weapon_pose_policy.lua` owns a pure unsupported-parent ledger. Each missing parent is recorded once. One ledger records at most `MAX_UNSUPPORTED_RECORDS = 32` parents; later distinct parents are only counted as suppressed. Nothing resets the ledger while the module is loaded (option flips, realm changes and wheel rebuilds keep it), so the bound is per loaded Cosmetics module generation.

- Automatic capture: each recorded parent emits `[cos:485] no authored pose catalog parent=<key> fallback=deferred record=<n>/32`.
- Tester summary: `/cos_485_diag` prints one `[cos:485:diag] summary recorded=<n> suppressed=<m> cap=32 parents=<keys>` line from the same ledger and never records anything itself.
- Regression: `issue485_authored_weapon_poses_local_only` proves the cap on a scratch ledger and checks that the live ledger is within its cap, so running `/cos_regression_test` never adds a probe parent to the evidence.
