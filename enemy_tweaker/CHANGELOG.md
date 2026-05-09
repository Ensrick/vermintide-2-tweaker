# Enemy Tweaker Changelog

## 0.2.4-dev (2026-05-06) — Fix init crash on NetworkLookup strict-lookup

- Mod failed to load with `[NetworkLookup.lua] Table breeds does not contain key: et_necro_skeleton`. The existence check `not nl_breeds[def.name]` was itself a GET that tripped the strict `__index` metatable before the key got written. Switched to `rawget` for the check; direct assignment is unchanged.

## 0.2.2-dev

CHANGELOG started after the fact — earlier dev iterations are not documented here. See `git log -- enemy_tweaker/` for the actual history.

Future entries should follow the format used by the other tweaker mods: one `## <version> (date) — <one-line summary>` heading per change set, with bullet points or a short paragraph below.
