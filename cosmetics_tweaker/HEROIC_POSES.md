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

Some modded or unusual weapon parents may have no authored pose rows or pose icon package. Reusing a random weapon's entries can combine the wrong animation vocabulary, icon paths, or package lifecycle. Those parents currently retain vanilla behavior and produce one bounded `[cos:485]` diagnostic. A donor fallback should ship only after the capture proves a compatible weapon family and package for each missing parent.
