# LA Prefix Patch Changelog

## 0.2.0-dev (2026-05-06)

### Initial release: suppress Loremaster's Armoury duplicate-hook warnings

Loremaster's Armoury (Workshop ID 2789506353) registers three duplicate
hooks in its `utils/hooks.lua` and emits `[WARNING] (hook): Attempting to
rehook active hook [...]` for each. The warnings echo to chat at startup,
drowning out other mods' version banners. The author has been silent for
3 years, so an upstream PR is not viable.

Duplicates being suppressed:
- `LevelEndView.start` (utils/hooks.lua:407 + 1173, byte-identical)
- `LevelTransitionHandler.load_current_level` (lines 423 + 1189, byte-identical)
- `LocalizationManager._base_lookup` (lines 298 + 1698, second is a strict subset
  of the first — silent replacement under VMF's `allow_rehooking` path would
  clobber LA's cosmetic skin-name swap)

### How it works

Loads above Loremaster's Armoury in launcher load order, wraps
`VMFMod.hook` / `hook_safe` / `hook_origin` on the **prototype**. The
wrapper checks `self:get_name() == "Loremasters-Armoury"` at hook-
registration time and silently drops any second call on the same
`(obj, method)` pair before VMF can warn about it. First registration
wins — correct semantics for all three of LA's dupes.

All other mods pass through the wrapper unchanged.

### Architectural notes

- VMF runs each mod's `mod_script` inside its own `new_mod()` call, so
  `get_mod("Loremasters-Armoury")` returns nil at our script-load time
  (LA hasn't been registered yet). v0.1.0-dev tried to grab LA's instance
  directly and silently no-op'd; v0.2.0-dev patches the VMFMod prototype
  instead, which propagates to all future instances via `__index` lookup.
- Ships zero LA code — purely runtime monkeypatching. No MIT attribution
  burden, no asset-licensing question.
- Required as a load-order partner for any future Cosmetics Tweaker
  integration that depends on LA being loaded but quiet.
