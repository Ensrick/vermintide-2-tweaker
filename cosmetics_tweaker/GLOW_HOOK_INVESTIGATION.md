# `_G.apply_material_settings` nil-at-hook-time investigation

Investigated 2026-05-19. Source citations are absolute paths into `C:\Users\danjo\source\repos\Vermintide-2-Source-Code`.

## 1. Why the `_G` hook is nil at boot

`apply_material_settings` is defined as a **bare global function** (no class table) at:

- `scripts\flow\flow_callbacks_foundation.lua:896` — `function apply_material_settings(unit, material_settings_name)`

In Lua 5.1, `function name(...)` at file scope assigns to `_G.name`. So the symbol DOES exist at runtime — but only *after* `flow_callbacks_foundation.lua` has been executed.

That file is **NOT** loaded eagerly:

- It is NOT in the require chain rooted at `scripts/boot.lua` `_require_foundation_scripts` (`boot.lua:515-520`).
- It is NOT required by `scripts/flow/flow_callbacks.lua` (which only requires `flow_callbacks_ai`, `_enemy`, `_progression`, then `DLCUtils.dofile("flow_callbacks")` — `flow_callbacks.lua:3-11`).
- It is NOT referenced as a DLC `flow_callbacks` setting (only `carousel_common_settings.lua:132` sets that, and it points at `flow_callbacks_vs`, not `_foundation`).
- A global `grep` for `flow_callbacks_foundation` across the entire decompiled source returns ZERO `require(...)` / `dofile(...)` matches anywhere in `.lua` files. The file appears only in the bundle dictionary (`vt2_bundle_unpacker\dictionary.txt:29480`).

The Stingray pattern is: flow-graph nodes can bind a string `script_data` field to the path of a Lua file. The engine loads that file the first time a flow node referencing it fires (typically on level-load or hub-enter). Until then, `apply_material_settings` is genuinely nil.

VMF mod scripts execute during boot, well before any level / hub flow graph runs, so at the moment `cosmetics_tweaker.lua` runs its top-level hook installation the symbol is undefined. The fallback log line `[GLOW] _G.apply_material_settings nil at hook time` (`cosmetics_tweaker.lua:2552`) is the expected outcome.

By the time the user is in the keep, `_G.apply_material_settings` IS populated — but our hook has already been skipped and never re-attempted.

## 2. The `_G` callsites are LIMITED — fallback is more complete than the doc suggested

Grep `apply_material_settings` across the decompiled source yields three distinct call-paths:

| Caller | Call-form | Where |
|---|---|---|
| `flow_callbacks_foundation.lua:580, 601, 617, 700, 717, 729, 804` | bare `apply_material_settings(...)` (the global) | `flow_callback_show_player_equipment`, `flow_callback_attach_player_item` — NPC display weapons / hub setpiece weapons / weapon-rack flow nodes |
| `gear_utils.lua:63-76, 198, 270`, `player_projectile_unit_extension.lua:54, 1323`, `player_projectile_husk_extension.lua:49, 846`, `simple_husk_inventory_extension.lua:680-693`, `world_hero_previewer.lua:1104`, `pickup_unit_extension.lua:50`, `demo_character_previewer.lua:596`, `loot_item_unit_previewer.lua:560` | `GearUtils.apply_material_settings(...)` | **All player-equip paths, both local + husks + projectiles + pickups + previewer + loot-preview** |
| `world_hero_previewer.lua:567`, `player_unit_cosmetic_extension.lua:144, 151` | `CosmeticUtils.apply_material_settings(...)` | Hat / armour cosmetic tints (1P + 3P) |

**The bare-global path is used ONLY by the flow-callback file**, which is for the static display weapons hub NPCs / weapon racks hold — NOT for the player's wielded weapons, ammo, projectiles, husks, or any inventory preview. The two class-table copies (`GearUtils.apply_material_settings`, `CosmeticUtils.apply_material_settings`) already cover the entire player-relevant glow surface that cosmetics_tweaker's override system targets.

The user's reported "glow customization broken" is therefore **not** caused by the missing `_G` hook — those flow-callback sites don't affect player weapons. Look elsewhere for the actual regression (see Section 5).

## 3. `GearUtils` / `CosmeticUtils` are tables — they ARE available at mod-load

- `gear_utils.lua:3` — `GearUtils = {}` (global table, populated by method assignments below).
- `cosmetic_utils.lua:3` — `CosmeticUtils = CosmeticUtils or {}` (global table).
- Both files are `require`d eagerly via `entity_system.lua` (`simple_inventory_extension.lua:4` → `inventory_system.lua:3` → `entity_system.lua:42`; `cosmetic_system.lua:3` → `entity_system.lua:20`).
- `entity_system.lua` itself is loaded during boot before VMF mods run, so by the time the mod's top-level code executes both `GearUtils.apply_material_settings` and `CosmeticUtils.apply_material_settings` already exist — confirmed by the boot log: `Hooking 'apply_material_settings' from [GearUtils]` and `from [CosmeticUtils]` both install successfully (`_pc_b_logs\pc_b_console_2026-05-19_19.44.33.log:1143, 1145`).

## 4. Recommended fix: deferred hook installation

The cleanest fix is to make the `_G` hook lazy — attempt it on mod load (existing), and if it fails, retry from `mod.on_game_state_changed` until it succeeds. The state-change callback fires reliably on every transition (boot → state_title → state_loading → state_keep, then again on level enter), and by the first level/hub transition the symbol is populated.

Why deferred-and-retry rather than only-retry: doing the install at mod-load when the symbol IS available (e.g. on a hot-reload after the game has already loaded a level once) preserves the current fast-path. If the symbol is nil, retry harmlessly later.

`mod.on_game_state_changed` already exists at `cosmetics_tweaker.lua:605` and is the right place to hang the retry. No new lifecycle plumbing required.

### Proposed patch (replaces lines 2548-2558)

```lua
_hook_apply_with_template_mutation("GearUtils", "gear")
if rawget(_G, "CosmeticUtils") and CosmeticUtils.apply_material_settings then
    _hook_apply_with_template_mutation("CosmeticUtils", "cosmetic")
else
    mod:info("[GLOW] CosmeticUtils.apply_material_settings nil at hook time")
end

-- `_G.apply_material_settings` is a bare global declared in
-- `scripts/flow/flow_callbacks_foundation.lua:896`. That file is loaded
-- lazily by the engine when a flow graph references it (typically the
-- first hub/level enter), NOT during boot. Try it now; if nil, retry from
-- on_game_state_changed below until it lands. Note this only affects
-- NPC/setpiece display weapons — player weapons / husks / projectiles /
-- previewer all go through GearUtils.apply_material_settings, already
-- hooked above.
local function _try_install_flow_glow_hook()
    if mod._glow_hooks_installed.flow then return true end
    if not _G.apply_material_settings then return false end
    _hook_apply_with_template_mutation(_G, "flow")
    mod:info("[GLOW] _G.apply_material_settings hook installed (deferred)")
    return true
end

if not _try_install_flow_glow_hook() then
    mod:info("[GLOW] _G.apply_material_settings nil at boot; will retry on game-state change")
end
mod._try_install_flow_glow_hook = _try_install_flow_glow_hook
```

Then in the existing `mod.on_game_state_changed` body (currently at line 605):

```lua
mod.on_game_state_changed = function()
    apply_cosmetic_unlocks()
    if mod._try_install_flow_glow_hook then mod._try_install_flow_glow_hook() end
end
```

### Gotchas walked

- **No duplicate hook registrations.** `_hook_apply_with_template_mutation` sets `mod._glow_hooks_installed.flow = true` after installing (`cosmetics_tweaker.lua:2545`), and `_try_install_flow_glow_hook` early-outs on that flag. This matters because `mod:hook` and `mod:hook_safe` both treat a second registration on the same Class+method as a *replacement*, not a chain (per `feedback_vmf_hook_safe_no_chain.md`).
- **`_G` as the class arg.** `mod:hook(_G, "method", ...)` is documented in VMF and confirmed in the codebase (e.g. `_G.Localize` hooks). Passing `_G` (table) + string method name is valid; VMF resolves `_G[method]` at install time, so we must NOT install until the symbol is set.
- **Class-derivation gotcha N/A.** `apply_material_settings` is a free function, not a method on a `class()` table, so the parent-method-copy concern from `feedback_vt2_class_hook_derived.md` doesn't apply.

## 5. Why glow customization may still be reported as broken

The `_G` nil-at-hook-time message is a red herring for player-glow regression. The fallback (`GearUtils` + `CosmeticUtils`) already covers every player-visible site that uses `MaterialSettingsTemplates`. If glow customization is genuinely broken in-game, candidate root causes:

- A recent rewrite of `_glow_rgb_for_var` / `_glow_var_mult` widget IDs that no longer match the saved VMF settings (silently returns nil → no override).
- The custom template `MaterialSettingsTemplates._cosmetics_tweaker_glow` registration (per the architecture note at `cosmetics_tweaker.lua:2560-2573`) may have regressed — verify the template is in the table and that `spawn_inventory_unit` injection still fires for `_runed_01`/`_magic_01` units.
- Husk weapons: `simple_husk_inventory_extension.lua` calls `GearUtils.apply_material_settings` (NOT a separate husk variant), so they SHOULD be covered. Confirm by enabling `glow_trace` and verifying the per-call counter increments while another player is in view.

Fixing the `_G` deferred hook is correct hygiene but will NOT by itself restore player-weapon glow. The investigation should hand off to whichever recent change in the override resolution path is suppressing the override.

## 6. Files cited

- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\flow\flow_callbacks_foundation.lua:896` — bare-global definition of `apply_material_settings`.
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\flow\flow_callbacks.lua:1-11` — top-of-tree require chain that does NOT pull in `_foundation`.
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\unit_extensions\default_player_unit\inventory\gear_utils.lua:3, 107` — `GearUtils = {}` and `GearUtils.apply_material_settings = function ...`.
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\helpers\cosmetic_utils.lua:3, 29` — `CosmeticUtils = CosmeticUtils or {}` and `CosmeticUtils.apply_material_settings = function ...`.
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\entity_system\entity_system.lua:20, 42` — eager require chain pulling both helper tables in at boot.
- `C:\Users\danjo\source\repos\vermintide-2-tweaker\cosmetics_tweaker\scripts\mods\cosmetics_tweaker\cosmetics_tweaker.lua:2496-2558` — current hook installation block (proposed-patch target).
- `C:\Users\danjo\source\repos\vermintide-2-tweaker\cosmetics_tweaker\scripts\mods\cosmetics_tweaker\cosmetics_tweaker.lua:605` — `mod.on_game_state_changed` existing entrypoint.
- `C:\Users\danjo\source\repos\vermintide-2-tweaker\cosmetics_tweaker\_pc_b_logs\pc_b_console_2026-05-19_19.44.33.log:1143-1145` — log line proving `GearUtils` installs, `_G` skipped, `CosmeticUtils` installs.
