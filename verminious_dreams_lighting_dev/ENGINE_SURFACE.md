# verminious_dreams_lighting_dev - engine contact surface

What vanilla VT2/Stingray does at every seam `verminious_dreams_lighting_dev`
(`vdl`) touches, and why the mod is there. This is the per-mod companion to the
subsystem set in `docs/engine/` (read `docs/engine/README.md` for house style). It
does **not** re-explain a subsystem the engine docs own, and it does **not**
duplicate the mod's `DEVELOPMENT.md` (per-mission lighting tuning architecture) -
it names each engine seam, cites the vanilla behavior, and links out. This
documents the ACTIVE dev stream (`verminious_dreams_lighting_dev/`), not stable
`verminious_dreams_lighting/`; the stable dir is read-only between promotions
(repo `CLAUDE.md`). Decompile paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `vdl` line numbers are
`verminious_dreams_lighting_dev.lua` unless noted. `§N` = a `docs/BUG_CLASSES.md`
class; `#N` / "issue N" = a GitHub issue. Grep-verified 2026-07-12 against the
decompile.

`vdl` overhauls the lighting of the three Verminious Dreams DLC missions
(`dlc_termite_1/2/3`) by overriding two engine surfaces per mission: the
per-frame ShadingEnvironment (sky/sun/atmosphere tint + exposure) and the level's
Light components (color/intensity). It is CLIENT-SIDE ONLY - it mutates render
state on the local machine, sends nothing over the wire, and carries no
host/version-sync risk. A second layer (v1.0.9-dev) composes a Chaos Wastes curse
tint on top when the same mission is played inside a Deus expedition, reading the
active deity theme straight off the vanilla Deus mechanism with no `ct` dependency.

## Hook table

2 registration sites, both `mod:hook_safe` (post-callback, no override). The Light
component overrides and the ShadingEnvironment writes are engine C-API calls made
INSIDE these two callbacks, not separate hooks; they are covered in the subsystem
notes.

### Per-frame shading override (per-frame row-of-concern) (owner doc: `docs/engine/09`)

| Class.method (kind) | Vanilla behavior at the seam | Why vdl hooks it | Trap / invariant |
|---|---|---|---|
| `CameraManager.shading_callback` [safe] `:639` | Per-frame shading callback; vanilla wraps its whole body in `if self._world == world` because UI/preview/end-screen worlds also drive it [src: `scripts/managers/camera/camera_manager.lua:283-284`] | Sample and then override the ShadingEnvironment vars (sky/sun/fog/atmosphere via `_SHADING_VARS`) + exposure for the current profiled mission; optionally multiply by the per-deity curse tint in CW (`:639`) | PER-FRAME ROW. Gated by `_profile_for_current_level()` returning non-nil, i.e. only on `dlc_termite_1/2/3` with the toggle on - so it is inert everywhere else. It writes SCALAR / VECTOR3 vars via `ShadingEnvironment.set_scalar` / `.set_vector3`, NOT a blend VARIATION, so it is not itself at risk of §22 (the shading-env VARIATION-blend native AV) - but §22 is the crash class in this exact neighborhood: any future code that writes an undefined env variation on a mission-substituted world is an uncatchable AV. Override reverts for FREE each frame (the engine re-seeds the env every frame), so a toggle-off short-circuits with no cleanup needed. The `self._world == world` distinction is not re-checked here; the profile gate is what keeps it from tinting unrelated worlds |

### Level-load light capture + apply (owner doc: `docs/engine/08`)

| Class.method (kind) | Vanilla behavior at the seam | Why vdl hooks it | Trap / invariant |
|---|---|---|---|
| `GameModeManager.local_player_game_starts` [safe] `:692` | Fires when the local player's game starts (level load); delegates to `self._game_mode:local_player_game_starts` [src: `scripts/managers/game_mode/game_mode_manager.lua:735`] | Resolve the raw engine level key to one of the 3 base profile keys, cache it, and run `_capture_and_apply_lights(self._world)` (`:692`) | Capture enumerates `Level.units(LevelHelper:current_level(world))` and, per unit, reads `Unit.num_lights` / `Unit.light` and `Unit.world_position` (Z is up) [src: engine C-API], caching each `Light` handle; apply calls `Light.set_color` / `Light.set_intensity` inside a `pcall` (`:564`-`:573`). Unlike the shading override, applied Light values PERSIST until the next level load - a toggle-off does not revert already-set lights this session (documented caveat, `:466-472`). `_deus_run_controller()` is read here for the CW diagnostic line |

## Subsystem notes (how the vanilla flow runs end-to-end, for vdl's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc and `DEVELOPMENT.md` carry the full architecture.

### Two override surfaces, two lifetimes (owner: `docs/engine/09`, `docs/engine/08`)

The ShadingEnvironment (atmosphere/sky/sun/exposure) is re-seeded by the engine
every frame, so vdl re-applies it every frame in `shading_callback` and it reverts
instantly when the profile gate closes. The Light components (per-lamp color +
intensity) are one-shot engine state set at level load, so vdl captures the handles
once in `local_player_game_starts` and applies to the cached list - meaning a
mid-mission toggle-off leaves the already-applied light values in place until the
next load (the same caveat as the `vdl_light_off` command). Lights are classified
per-unit into `torches` vs `general` by a name-substring match and a below-map
Z-height test (`_classify_light`, `:523`), so a profile can tune torch lamps
separately from ambient lamps.

### The per-frame contract (owner: `docs/engine/09`; parallel: event_tweaker's shading hook)

`shading_callback` is one of the hottest callbacks in the engine. The event_tweaker
Cursed-Adventure shading hook documents the same contract: mirror the vanilla
`self._world == world` intent, read only file-local upvalues, and allocate nothing
per frame. `vdl` reads `_SHADING_VARS` / `_CURSE_VARS` / `_CURSE_ADJUST` as
file-local upvalues and short-circuits before touching the engine boundary when no
profile is active (`_apply_lights_to_cached` has the equivalent `any_set`
short-circuit at `:540`). The curse-multiply layer reads the post-LAYER-1 value
back out and multiplies in place, so the curse look composes on top of vdl's custom
color rather than replacing it.

### Vanilla Deus state reading, no ct dependency (owner: `docs/engine/07`)

The CW curse layer reads the active expedition's theme directly off the vanilla
Deus mechanism: `Managers.mechanism:game_mechanism():get_deus_run_controller()`
[src: `scripts/managers/game_mode/mechanisms/deus_mechanism.lua:523`] ->
`run:get_current_node()` -> `node.theme` (one of the `DEUS_THEME_TYPES`:
khorne/nurgle/tzeentch/slaanesh/belakor/wastes) [src: `deus_theme_settings.lua:120-127`
per code comment]. Outside a Deus expedition the mechanism has no
`get_deus_run_controller` method, so every reader bails nil and the whole curse
layer no-ops (`:436`-`:463`). vdl branches its tint on the THEME (the deity),
because that is the value with a verifiable vanilla `light_probe_tint` and a clean
1:1 set of 5 deities; `node.curse` (the granular curse mutator name) is surfaced
to the user for diagnostics but the lighting does not branch on it.

## What the engine will NOT let us do (dead ends, already paid for)

Pulled from the code comments, `docs/BUG_CLASSES.md`, and `DEVELOPMENT.md` - do not
re-discover these.

- **A shading-env override cannot be made sticky, and does not need cleanup.** The
  engine re-seeds the ShadingEnvironment every frame, so there is no "set it once"
  path - vdl must re-apply in the per-frame callback, and conversely a disabled
  profile reverts for free (no restore code). Do not add teardown logic for the
  shading layer.
- **Applied Light-component values do NOT auto-revert.** `Light.set_color` /
  `Light.set_intensity` mutate persistent engine state set at level load, so a
  mid-mission toggle-off leaves them until the next load. This asymmetry with the
  shading layer is inherent; document it in the toggle tooltip rather than trying
  to snapshot-and-restore every light (`:466-472`).
- **Writing an undefined ShadingEnvironment blend VARIATION is an uncatchable
  native AV (§22).** vdl currently writes only scalar/vector3 env vars, which are
  safe, but the moment any code requests a blend variation the env does not define
  on a mission-substituted world, it is a 0xc0000005 access violation on a rendered
  frame that no `pcall` can catch [src: `docs/BUG_CLASSES.md` §22]. If vdl ever
  reaches for variation-level control, it must pick the env by residency and pin
  the variation, per the §22 fix template - not assume the variation exists.
- **The Deus theme, not the curse, is the lighting key.** Many curses map onto one
  deity theme, and only the theme carries a verifiable vanilla light tint
  (`light_probe_tint`); branching lighting per-`node.curse` would multiply the
  branch count with no reliable per-curse tint reference. Key the adjustment on
  `node.theme` and surface `node.curse` for the user only.

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if a vdl hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row in
the SAME commit. This doc documents the ACTIVE `verminious_dreams_lighting_dev`
stream; on promotion to stable, copy it into `verminious_dreams_lighting/` with the
mod id and line refs adjusted (do not edit the stable copy between promotions). It
complements, and must not duplicate, `DEVELOPMENT.md` (the per-mission tuning
architecture). The load-bearing citations (`camera_manager.lua:283-284`,
`game_mode_manager.lua:735`, `deus_mechanism.lua:523`) were verified this pass; the
`deus_theme_settings.lua:120-127` / `deus_generate_graph.lua:68` node-field lines
are cited from the mod's own decompile research. Line numbers are against the
2026-07-12 decompile - match crash logs by function name, not line. Section shape
(hook table -> subsystem notes -> dead ends) matches
`character_weapon_variants/ENGINE_SURFACE.md`. Reverse index:
`docs/engine/README.md` "Per-mod surface docs".
