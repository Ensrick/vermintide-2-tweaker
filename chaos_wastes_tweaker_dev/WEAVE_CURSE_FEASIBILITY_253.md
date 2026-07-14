# Weave winds as Chaos Wastes curses (#253)

## Source findings

The candidate set is exactly eight winds: Metal, Fire, Heavens, Life, Shadow,
Death, Light, and Beasts. `WindSettings` maps each wind to an identically named
mutator, and `WeaveManager.mutators` supplies that one mutator to `GameModeWeave`
(`scripts/settings/wind_settings.lua`; `scripts/managers/weave/weave_manager.lua:520-540`).
They are already global `MutatorTemplates` and network lookup entries through
`mutator_settings.lua:24-31`; new RPC or lookup values are unnecessary.

Directly adding these names to a Deus curse list is unsafe:

- all eight start functions read `Managers.weave` for wind strength/settings;
- Light and Beasts also dereference the active Weave objective and spawn its
  `mutator_item_config`, which does not exist on a Chaos Wastes level;
- Heavens, Life, Shadow, Death, Light, and Beasts use Weave units/effects or
  objective-spawned units;
- none of the eight templates declares `packages`, while Deus only preloads event
  mutator packages from that field (`deus_run_state.lua:438-461`).

`[ct:253]` records this catalog twice at most (load and first `StateIngame`) and
checks six known unit resources with `Application.can_get`. It never activates or
registers a mutator.

## Staged potential fix

Use per-level curses, not run-persistent event mutators. This matches Chaos Wastes'
node curse lifecycle and avoids carrying world units across teardown. Each wind
gets an independent default-off toggle and a host-owned strength setting.

1. **Metal first:** replace its unused `Managers.weave:get_wind_strength()` read
   with an explicit CT context value and validate armor restoration. It spawns no
   wind unit and is the smallest proof of the context bridge.
2. **Fire next:** bridge explicit settings/strength; validate its existing buff
   and network behavior without adding transport.
3. **Heavens/Life/Shadow/Death:** declare and preload exact resources, supply a
   bounded CT context, and verify teardown/hot join one wind at a time.
4. **Light/Beasts last:** author Deus-native placement rules. Never synthesize a
   fake Weave objective merely to satisfy `mutator_item_config`; that would import
   arena/objective ownership into unrelated maps.

The context adapter must expose only the values a selected wind consumes; it must
not replace global `Managers.weave`, because other installed mods and Weave menus
own that manager. Activation must occur before `MutatorHandler` initialization so
the host's initialized map and vanilla hot-join RPC remain authoritative.

## Verification boundary

Every implemented wind requires two-player verification: host/client activation,
late join, level transition, death/respawn, curse stacking, resource residency,
and exact cleanup. Metal also needs armored/unarmored enemies as controls. Until a
wind passes that matrix, it remains absent from the selectable curse menu.
