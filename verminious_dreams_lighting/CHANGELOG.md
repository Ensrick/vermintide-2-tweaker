# Verminious Dreams Lighting — Changelog

## v0.8.0-alpha (2026-05-16)

**First public release.** Flipped visibility from `friends_only` → `public`. All three Verminious Dreams missions are baked: The Forsaken Temple, Devious Delvings, The Well of Dreams. Subscribers get tuned lighting on `dlc_termite_1/2/3` out of the box; per-mission VMF toggles default ON.

Updated Workshop description to match the rest of the Tweaker family — feature bullets, multiplayer note (client-side only), source link, BMC button.

## v0.8.0-dev (2026-05-16)

**Baked The Well of Dreams defaults** from the first tuning pass:

```
dlc_termite_3 = {
    sun = { 100, 100, 100 },
    amb = { 200, 200, 280 },
    amb_top = { 50, 50, 60 },
    fog = { 70, 85, 85 },
}
```

(sky, sun2, exp, and light overrides left vanilla.)

**All three Verminious Dreams missions are now baked.** Subscribers get tuned lighting on `dlc_termite_1/2/3` out of the box, with the per-mission VMF toggles defaulting to ON. Bumped the localization tooltip to remove the "no-op" caveat from The Well of Dreams.

## v0.7.0-dev (2026-05-16)

**Baked Devious Delvings defaults** from the first tuning pass:

```
dlc_termite_2 = {
    sun = { 160, 120, 80 },
    amb = { 250, 250, 250 },
    amb_top = { 50, 100, 160 },
    fog = { 24, 24, 24 },
}
```

(sky, sun2, exp, and light overrides left vanilla.) Subscribers now get this lighting on `dlc_termite_2` without running any commands. One mission left to tune (`dlc_termite_3` / The Well of Dreams).

Bump localization to remove the "(currently a no-op)" note from the Devious Delvings toggle tooltip.

## v0.6.0-dev (2026-05-16)

Dropped the chasm light group. The position-based detection wasn't catching the lights it was supposed to in actual play — the chasm lights apparently aren't attached to level-static units the way torches are, so `Level.units` / `Unit.world_position` doesn't reach them. Could pursue (e.g. `Light.position`, or a per-light position read off the Light handle), but parking the feature instead.

Removed commands: `vdl_chasm`, `vdl_chasm_int`, `vdl_chasm_y`. Removed profile fields: `light_chasm_color`, `light_chasm_intensity`, `chasm_y_max`. Saved profiles with those fields silently ignore the unknown keys on hydration.

Light groups are now just **torches** and **general**.

## v0.5.0-dev (2026-05-16)

Per-mission VMF toggle. Each of the three Verminious Dreams missions has its own checkbox in the mod's VMF settings menu, defaulting to ON. Switching one OFF returns that mission to vanilla lighting without disabling the whole mod (or losing your tuned values — they stay in `_PROFILES` ready for re-enable).

- `enable_dlc_termite_1` — "The Forsaken Temple" (default ON)
- `enable_dlc_termite_2` — "Devious Delvings" (default ON)
- `enable_dlc_termite_3` — "The Well of Dreams" (default ON)

Mid-mission toggle flip behavior:
- Atmosphere (sky / sun / fog / ambient / exposure) reverts immediately because the shading_callback hook short-circuits when the toggle is off and the engine re-seeds those values from the level template every frame.
- Per-light Light component overrides only fully clear on next level load. The Stingray engine doesn't expose `Light.color` / `Light.intensity` for read-back, so once we've set values on a Light handle there's no path back to the vanilla baked value mid-mission. Flipping the toggle BACK ON via `mod.on_setting_changed` does reapply immediately.

`/vdl_*` commands still work when a toggle is OFF (so you can tune at any time); they print a one-line note reminding you the toggle is off, and your edits queue up — flipping the toggle on applies them.

## v0.4.0-dev (2026-05-16)

**Baked The Forsaken Temple defaults** from the first tuning pass:

```
dlc_termite_1 = {
    sky = { 50, 100, 170 }, sun = { 210, 210, 230 }, sun2 = { 255, 255, 255 },
    amb = { 210, 210, 180 }, amb_top = { 150, 150, 200 }, fog = { 86, 90, 70 },
    exp = 0.045,
}
```

Subscribers now get this lighting on `dlc_termite_1` without running any commands.

### Per-light-group control

Global `vdl_light` paints every Light in the level the same colour, which is too coarse — torches and chasm-floor lights need to look different. Lights now auto-classify into three groups at level start:

- **torches** — parent unit's debug name contains `torch / brazier / candle / lantern / sconce` (case-insensitive). Override the pattern list with `vdl_torch_patterns`.
- **chasm** — parent unit's world Z is below `chasm_y_max`. Disabled until you set a threshold via `vdl_chasm_y <value>`. Stingray engine has Z up — "below the map" means low Z, not low Y.
- **general** — everything else.

Apply precedence per light: specific-group override → global `light_color` / `light_intensity` → vanilla.

### New commands

- `vdl_torch [r g b]` / `vdl_torch_int [val]` — paint torches group
- `vdl_torch_patterns [list|reset]` — override which substrings count as torches
- `vdl_chasm [r g b]` / `vdl_chasm_int [val]` — paint chasm group
- `vdl_chasm_y [val]` — set Z threshold for chasm group
- `vdl_lights` — counts per group + parent Z range (use the range to pick a sensible `vdl_chasm_y`)
- `vdl_lights_list [pattern]` — list cached lights with index / group / Z / unit debug_name; great for spotting which units own which lights

`vdl_light` and `vdl_light_int` still work as the global fallback for ungrouped lights.

### Storage / compat

- Saved-storage key bumped to `saved_profiles_v4` (additive fields on top of v0.3).

## v0.3.0-dev (2026-05-16)

**Interface uses 0-255 byte RGB now** (like web / hex colors), not 0-1 floats.

- `vdl_sun` prints e.g. `vanilla = 243 216 176` — same numbers you'd see in any color picker.
- `vdl_sun 200 255 172` sets sun_color to that byte triple.
- HDR values above 255 are accepted — some engine baselines exceed 1.0 (e.g. sun_color baseline ~380 = engine value 1.49). Type a bigger byte and you get a brighter-than-full light.
- `_PROFILES` literals in the source file are byte triples: `sun = { 200, 255, 172 }`. What `vdl_dump` prints is the exact format you paste into source.
- `exp` and `light_intensity` remain scalars (NOT bytes — exposure is EV-like, light intensity can be 50-5000+ for HDR point lights).
- Saved-storage key bumped to `saved_profiles_v3` so v0.2 float profiles aren't reinterpreted as bytes.

## v0.2.0-dev (2026-05-16)

**Breaking semantics change**: every command now takes ABSOLUTE values, not multipliers.

- `vdl_sun 0.9 0.7 0.5` now sets sun_color to exactly that RGB triple (was: multiplied vanilla by it).
- Every command also works with NO arguments — `vdl_sun` prints both the current vanilla value (sampled live each frame) and the active override, if any. So you can read what the engine is using before deciding what to set.
- Added `vdl_clear <field>` (e.g. `vdl_clear sun`, `vdl_clear all`) to remove an override and return that channel to vanilla.
- `vdl_light_mul` renamed `vdl_light_int` (absolute intensity, not a multiplier).
- Dropped `vdl_light_off / vdl_light_on`; light override is now implicit (presence of `light_color` / `light_intensity` = enabled, absence = vanilla).
- Storage key bumped to `saved_profiles_v2` so v0.1 multipliers don't get reinterpreted as absolutes.

## v0.1.0-dev (2026-05-16)

Initial release. Replaces lighting on the three Verminious Dreams DLC missions whose vanilla lighting reads as too dark / muddy:

- `dlc_termite_1` — The Forsaken Temple
- `dlc_termite_2` — Devious Delvings
- `dlc_termite_3` — The Well of Dreams

### What it does

For these three levels (and ONLY these three), the mod applies tuned multipliers on top of the level's baked lighting:

1. **Sky / sun / fog / ambient / exposure** — via `CameraManager.shading_callback` (per-frame multiplicative on ShadingEnvironment vars). Reverts automatically when leaving the level.
2. **Per-light colour + intensity** — via `Light.set_color` / `Light.set_intensity` on every Light component in `Level.units(level)`, applied once on `GameModeManager.local_player_game_starts`.
3. **Particle FX** — not in v0.1.0. Vanilla torches / glows are particle systems, not Light components; deferred (would require shipping per-effect material overrides).

v0.1.0 ships with all profiles at neutral 1.0 multipliers — same as vanilla — pending the live in-game tuning pass. After tuning, the resolved values get baked into `_PROFILES` in the source as the new default.

### Commands (in-game console, all prefixed `vdl_`)

- `vdl_sky r g b` — skydome_tint_color multiplier
- `vdl_sun r g b` — sun_color multiplier
- `vdl_sun2 r g b` — secondary_sun_color multiplier
- `vdl_amb r g b` — ambient_tint multiplier
- `vdl_amb_top r g b` — ambient_tint_top multiplier
- `vdl_fog r g b` — fog_color multiplier
- `vdl_exp <mul>` — exposure multiplier (scalar, default 1.0)
- `vdl_light r g b` — per-light Light.set_color multiplier (enables override)
- `vdl_light_mul <mul>` — per-light intensity multiplier (enables override)
- `vdl_light_off` / `vdl_light_on` — toggle override
- `vdl_reapply` — re-capture baseline + re-apply current profile
- `vdl_dump` — print current profile
- `vdl_save` — persist all profiles to VMF settings (survives restart)
- `vdl_reset` — reset current level's profile to 1.0
- `vdl_level` — print current level_key + profile status
- `vdl_help` — list commands
