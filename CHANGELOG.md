# Changelog

## [2026-04-23]
### Changed
- Modularized the project into three separate mods: `weapon_tweaker`, `career_tweaker`, and `chaos_wastes_tweaker`.
- Updated `weapon_tweaker` with the core weapon unlocking and animation logic.

### Fixed
- Fixed a fatal Stingray compiler crash caused by missing `valid_tags` in `lua_preprocessor_defines.config`.
- Improved hook safety in `weapon_tweaker.lua` to prevent engine-level assertion failures when pcall fails.

### Added
- Aggressive debug logging for weapon creation, animation events, and slot wielding in `weapon_tweaker`.
- New `enable_weapon_debug_logging` setting to toggle detailed logs.

## [2026-04-21]
### Fixed
- Fixed `BackendUtils.get_item_units` hook that was causing crashes by incorrectly handling return values.
- Fixed `apply_weapon_unlocks` to correctly restore `can_wield` to `nil` when the original was `nil`.
