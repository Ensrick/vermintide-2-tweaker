# Verminious Dreams Lighting — Development Notes

Architecture and live-tuning workflow for `verminious_dreams_lighting`.
Read alongside `CHANGELOG.md` (history) and `REGRESSION_CHECKLIST.md`
(pre-release gates).

---

## Overview

VMB mod, **renamed + republished 2026-05-16**. Predecessor
`lighting_tweaker` (Workshop 3727161095) was deleted by the user;
archived at `old-backup/lighting_tweaker_20260516/` for reference.

- Internal ID: `verminious_dreams_lighting` (command prefix: `vdl_`)
- Workshop ID: **3727221800** (public alpha since 2026-05-16; was
  friends_only earlier same day)
- Visibility: **public**

## Mission

Replace the lighting on three Verminious Dreams DLC missions whose
vanilla lighting is too dark / muddy:

| level_key | Display name |
|-----------|--------------|
| `dlc_termite_1` | The Forsaken Temple |
| `dlc_termite_2` | Devious Delvings |
| `dlc_termite_3` | The Well of Dreams |

(Verified via
`chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_adventure_pool.lua:137-139`.)

Final intent: ship hand-tuned `_PROFILES` values as the DEFAULT
lighting for these missions so subscribers don't have to run any
commands. Commands remain available for further tuning. The tuning
pass (run by the user in-game) produces `vdl_dump`-printed value
blocks that get pasted into `_PROFILES` in source.

All three missions are now baked (as of v0.8.0-dev / v1.0.0). Per-mission
VMF toggles default ON.

---

## Architecture

Two-layer pipeline, both gated on `_PROFILES[level_key] != nil`:

1. **ShadingEnvironment (sky/sun/fog/ambient/exposure)** —
   `mod:hook_safe("CameraManager", "shading_callback", ...)` multiplies
   per-frame shading-env values. Engine re-seeds from baked template
   every frame so leaving the level reverts automatically. **Same
   pattern Chaos Wastes Tweaker uses for curse-themed skies
   (`chaos_wastes_tweaker.lua:1378`).**

2. **Light components** — `mod:hook_safe("GameModeManager", "local_player_game_starts", ...)`
   walks `Level.units(level)` → `Unit.num_lights/Unit.light` → captures
   baseline (pcall-guarded since `Light.color`/`Light.intensity`
   read-side APIs may not exist) → applies tint via `Light.set_color`
   + `Light.set_intensity`. Gated on `profile.light_override_enabled`
   so default state ("user hasn't tuned lights yet") leaves vanilla
   untouched — flips true on first `vdl_light` / `vdl_light_mul`.

Hook on `GameModeManager` (the dispatcher), not a specific game mode
subclass, so the mod fires for vanilla adventure runs AND CW-injected
runs.

### Chaos Wastes application + curse-adjustment layer (v1.0.9-dev)

vdl's three missions exist twice under different `level_id` forms:

| Realm | `level_id` form | Example |
|---|---|---|
| Adventure | the raw base key | `dlc_termite_1` |
| Chaos Wastes | per-theme permutation `<base>_<theme>_path<N>` | `dlc_termite_1_khorne_path1` |
| Chaos Wastes (dup alias) | `<base>_dup<N>_<theme>_path<N>` | `dlc_termite_1_dup1_khorne_path1` |

The base mission key is always a literal prefix of the CW permutation, so
`_resolve_profile_key(raw_key)` does an exact match first (Adventure
unchanged) then a `^<base>_` prefix scan. This is the same convention
`chaos_wastes_tweaker`'s `adventure_base_from_level_key`
(`chaos_wastes_tweaker_dev.lua:3317`) relies on — but **vdl has no
dependency on ct**; it only reuses the naming pattern. Every level-key
lookup (`local_player_game_starts`, `shading_callback`,
`on_setting_changed`, `_profile_for_current_level[_raw]`, `vdl_level`)
resolves to the base key, and `_CURRENT_LEVEL_KEY` caches the base.

**Curse layer (Layer 2)** — folded into the existing `shading_callback`
hook (no second hook on `CameraManager.shading_callback` — that would be a
silent VMF no-chain drop). After Layer 1 sets vdl's base colors, if we're
in a Deus expedition with a curse (theme ≠ `wastes`), Layer 2 reads the
post-base ShadingEnvironment value back out and multiplies it by a
per-deity tint, composing the curse look ON TOP of vdl's lighting.

- **Curse/theme read from vanilla Deus state only:**
  `Managers.mechanism:game_mechanism():get_deus_run_controller():get_current_node().theme`
  / `.curse` (nil-safe via `_deus_run_controller` / `_current_deus_node`).
  `node.theme` = the deity (`DEUS_THEME_TYPES`: khorne/nurgle/tzeentch/
  slaanesh/belakor/wastes); `node.curse` = the granular curse mutator name
  (e.g. `curse_belakor_totems`). vdl branches its lighting on the **theme**
  (5 deities, each with a verifiable vanilla tint); `node.curse` is surfaced
  to the user but not used to branch the color.
- **Seed = vanilla `DeusThemeSettings[theme].light_probe_tint`**, read live
  from the engine table (`deus_theme_settings.lua:9-14/23-27/46-50/66-70/
  86-90/106-110`). No fabricated curse colors are baked into vdl source —
  `_CURSE_ADJUST` starts empty and the user tunes per-deity via
  `/vdl_curse*`. Tuned values bake into `_CURSE_ADJUST` (separate save key
  `saved_curse_adjust_v1`).
- Master toggle `enable_cw_curse_adjust` (default ON, no-op outside CW).

**Open design choice:** Layer 2 multiplies vdl's base color (same idiom
ct uses for CW skies at `chaos_wastes_tweaker_dev.lua:4100`). A lerp toward
the vanilla curse atmosphere, or an additive overlay, are alternatives —
swap in Layer 2 if a different composition reads better in-game.

### Light grouping (v0.4.0+)

Global `vdl_light` paints every Light in the level the same colour,
which is too coarse — torches and chasm-floor lights need to look
different. Lights auto-classify into groups at level start:

- **torches** — parent unit's debug name contains
  `torch / brazier / candle / lantern / sconce` (case-insensitive).
  Override the pattern list with `vdl_torch_patterns`.
- **general** — everything else.

The **chasm** group was dropped at v0.6.0 — the position-based
detection wasn't catching the lights it was supposed to in actual play
(chasm lights apparently aren't attached to level-static units the way
torches are, so `Level.units` / `Unit.world_position` doesn't reach
them).

Apply precedence per light: specific-group override → global
`light_color` / `light_intensity` → vanilla.

### Per-mission VMF toggle (v0.5.0+)

Each Verminious Dreams mission has its own checkbox in the mod's VMF
settings menu, defaulting to ON:

- `enable_dlc_termite_1` — "The Forsaken Temple"
- `enable_dlc_termite_2` — "Devious Delvings"
- `enable_dlc_termite_3` — "The Well of Dreams"

Switching one OFF returns that mission to vanilla lighting without
disabling the whole mod (or losing tuned values — they stay in
`_PROFILES` ready for re-enable).

Mid-mission toggle flip behavior:

- Atmosphere (sky / sun / fog / ambient / exposure) reverts immediately
  because the shading_callback hook short-circuits when the toggle is
  off and the engine re-seeds those values from the level template
  every frame.
- Per-light Light component overrides only fully clear on next level
  load. The Stingray engine doesn't expose `Light.color` /
  `Light.intensity` for read-back, so once we've set values on a Light
  handle there's no path back to the vanilla baked value mid-mission.
  Flipping the toggle BACK ON via `mod.on_setting_changed` does
  reapply immediately.

`/vdl_*` commands still work when a toggle is OFF (so you can tune at
any time); they print a one-line note reminding you the toggle is off,
and your edits queue up — flipping the toggle on applies them.

---

## Commands (all prefixed `vdl_`)

### ShadingEnvironment (absolute values as of v0.2.0, byte-RGB as of v0.3.0)

Every command takes ABSOLUTE values (not multipliers) since v0.2.0.
Numbers are 0-255 byte RGB (like web/hex colors) since v0.3.0 — same
numbers you'd see in any color picker. HDR values above 255 are
accepted — some engine baselines exceed 1.0 (e.g. sun_color baseline
~380 = engine value 1.49).

- `vdl_sky r g b` — skydome_tint_color
- `vdl_sun r g b` — sun_color
- `vdl_sun2 r g b` — secondary_sun_color
- `vdl_amb r g b` — ambient_tint
- `vdl_amb_top r g b` — ambient_tint_top
- `vdl_fog r g b` — fog_color
- `vdl_exp <val>` — exposure (scalar, NOT a byte — EV-like)

Every command also works with NO arguments — prints both the current
vanilla value (sampled live each frame) and the active override, if
any. So you can read what the engine is using before deciding what to
set.

`vdl_clear <field>` (e.g. `vdl_clear sun`, `vdl_clear all`) removes an
override and returns that channel to vanilla.

### Light components

- `vdl_light r g b` — global per-light Light.set_color (enables override)
- `vdl_light_int <val>` — global per-light intensity (NOT a byte —
  50-5000+ for HDR point lights)
- `vdl_torch r g b` / `vdl_torch_int <val>` — paint torches group
- `vdl_torch_patterns [list|reset]` — override which substrings count
  as torches
- `vdl_lights` — counts per group + parent Z range
- `vdl_lights_list [pattern]` — list cached lights with index / group /
  Z / unit debug_name; great for spotting which units own which lights
- `vdl_reapply` — re-capture baseline + re-apply current profile

### Profile management

- `vdl_dump` — print current profile (copy-pasteable block; the literal
  byte-triple format the source `_PROFILES` uses)
- `vdl_save` — persist all profiles to VMF settings (survives restart;
  current storage key `saved_profiles_v4`)
- `vdl_reset` — reset current level's profile
- `vdl_level` — print current level_key + profile status
- `vdl_help` — list commands

---

## Particle FX — out of scope

Torches / magic glows are particle systems (not Light components).
`Light.set_color` doesn't tint them. Two implementation paths sketched
in `verminious_dreams_lighting.lua` bottom-of-file:

1. Hook `World.create_particles`, set particle-material tint vector.
2. Ship cloned `.particles` + `.material` assets with re-coloured
   variants.

**Not shipping.** Formally out of scope at v1.0.0 (was previously
deferred at v0.1.0). The engine paths have known cost/complexity that
isn't justified for a three-mission lighting mod.

---

## Build & deploy

```powershell
$exe = "C:\Users\danjo\source\repos\vermintide-2-tweaker\tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe"
& $exe build  verminious_dreams_lighting
& $exe all    verminious_dreams_lighting --allow-public
```

Public visibility requires `--allow-public` per launcher doctrine; `all`
also runs deploy so the author's local install picks up the new bundle
without waiting on Steam. After a tuning pass:

1. In-game, run `vdl_dump` to print the resolved values block.
2. Paste into `_PROFILES` in
   `scripts/mods/verminious_dreams_lighting/verminious_dreams_lighting.lua`.
3. Bump `MOD_VERSION` per the always-bump rule.
4. Republish.

Preview: placeholder lives at `item_preview.png` — was copied from
event_tweaker pre-public; verify before transitioning visibility.

---

## Status

- Build: `VMBLauncher.exe build verminious_dreams_lighting` →
  `verminious_dreams_lighting/bundleV2/` (4 bundles + .mod)
- Upload: `VMBLauncher.exe all verminious_dreams_lighting --allow-public`
