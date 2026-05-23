# Glow System — cosmetics_tweaker

State as of v0.9.7-glow+previewBid (2026-05-21).

This is the canonical reference for how the glow customization system is
wired today: which shader variables drive what visually, how the popup UI
talks to them, how persistence works, what the current limitations are,
and where to extend.

## 1. What's working today (v0.9.7)

| Surface | Status |
| --- | --- |
| `/glow_picker` chat command opens the popup | ✅ |
| 4 sliders: Red, Green, Blue, Intensity | ✅ |
| RUNE family live preview on wielded weapon | ✅ |
| RUNE family live preview on cosmetic-screen previewer | ✅ (v0.9.7 fix) |
| Per-backend_id persistence to VMF setting `glow_per_item` | ✅ |
| Restores saved RGB+intensity on popup re-open | ✅ |
| Per-item RGB takes precedence over global override toggle | ✅ |
| Magic-family multi-component sliders (lower / upper / dots) | ❌ (M3) |
| Auto-open popup on equip of a glow-capable item | ❌ (M3) |
| Toggle the per-item glow off entirely | ❌ (M3) |
| Hide vanilla glow-cousin items from cosmetic menu | ❌ (M3) |
| Cross-slot inheritance (main weapon glow → compatible shield) | ❌ (M3) |
| Coop broadcast of per-item glow to peers | ❌ (M3) |

## 2. The two glow families

VT2's themed Veteran weapons come in two glow families. Both work by
writing HDR-scaled colors into specific shader Vector3 variables on the
weapon unit's material.

### RUNE family (`_runed_01..06` suffix)

* **One** shader variable: `rune_emissive_color`
* Native template brightness: **9**
* Visual: a single glowing rune motif on the blade/handle.
* User-visible component count: **1** (4 sliders total: R, G, B, intensity).

### MAGIC family (`_magic_01` Weavebound, `_magic_02` Shyish-Infused)

* **Five** shader variables across **three** visual components:

  | Visual component | Shader var(s) | Native brightness |
  | --- | --- | --- |
  | Lower gradient | `color_glow_high` | 4 |
  | | `color_glow_low` | 1 |
  | Upper gradient | `color_smoke_high` | 0.22 |
  | | `color_smoke_low` | 0.06 |
  | Dots | `color_dots` | 8.35 |

* The brightness pairs within each gradient are coordinated by vanilla
  to produce a smooth visual transition. Our HDR scaling multiplies the
  user's RGB by each variable's native brightness to preserve that
  proportional structure.
* User-visible component count: **3** (12 sliders total: 4 per
  component for R/G/B/intensity).

## 3. Code references

All paths relative to `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/`.

| File | Role |
| --- | --- |
| `_glow_picker.lua` | The popup UI. Scenegraph, slider widget factory, in-memory state, persistence helpers (`_load_per_item_glow` / `_save_per_item_glow`), live-preview wiring. |
| `cosmetics_tweaker.lua` | Glow apply pipeline. `_GLOW_VAR_BRIGHTNESS` table, `_glow_rgb_for_var`, `_apply_glow_to_unit`, weak-table `mod._unit_to_backend_id`, runtime map `mod._per_item_glow_runtime`, helper `mod._reapply_glow_on_wielded`. |
| `cosmetics_tweaker_data.lua` | Existing global glow VMF settings (master toggle, presets, per-channel dropdowns). These are the "old" UI; the popup is the per-item UI that supersedes them. |

### Key tables and functions

`_GLOW_VAR_BRIGHTNESS` (cosmetics_tweaker.lua ~L2890) — maps every shader
variable to its native brightness, VMF setting key, and component group
(`"rune" / "lower" / "upper" / "dots"`).

`_GLOW_GROUP_COLOR_SETTING` (cosmetics_tweaker.lua ~L2903) — maps each
component group to the global per-channel-color VMF dropdown.

`mod._unit_to_backend_id` (cosmetics_tweaker.lua ~L2989) — weak-keyed
`{ [unit] = backend_id }` map. Populated by:
* `GearUtils.create_equipment` hook (in-keep, in-mission)
* `HeroPreviewer._spawn_item_unit` / `MenuWorldPreviewer._spawn_item_unit`
  hooks, via the `self._cos_current_equip_backend_id` field that the
  `equip_item` hooks captured (v0.9.7 fix)

`mod._per_item_glow_runtime` (cosmetics_tweaker.lua, runtime) —
in-memory `{ [backend_id] = { rune = {r,g,b,intensity} } }`. Set by:
* `GlowPicker.open_for(backend_id, slot_data)` — loads persisted state
  from `glow_per_item` VMF setting
* Slider drag `on_change` callbacks — write live to this map

`_apply_glow_to_unit(unit, owner_peer_id)` (cosmetics_tweaker.lua ~L3098)
— the load-bearing function. Checks `mod._per_item_glow_runtime[bid]`
FIRST (before the global toggle gate). For RUNE the path is:

```lua
local intensity   = pi.rune.intensity
local rune_native = _GLOW_VAR_BRIGHTNESS["rune_emissive_color"].brightness  -- 9
local scale       = rune_native * intensity / 255
Unit.set_vector3_for_materials(unit, "rune_emissive_color",
    Vector3(pi.rune.r * scale, pi.rune.g * scale, pi.rune.b * scale))
```

After per-item RUNE applies, the function `return`s — global override
does NOT also paint that channel. Magic-family channels (when M3 lands)
will need analogous early returns within their own per-component branches.

`mod._reapply_glow_on_wielded()` (cosmetics_tweaker.lua ~L3119) — helper
called by the picker's slider `on_change`. Walks `slot_data.{left,right}_unit_{1p,3p}`
and re-fires `_apply_glow_to_unit` on each. The cosmetic-screen previewer
units also get refreshed because they're in `mod._unit_to_backend_id`
(v0.9.7 fix via `equip_item` hook).

## 4. Persistence

Single VMF setting `glow_per_item` (string). JSON-encoded via the global
`cjson` library:

```json
{
  "08fab327-10c2-46b9-9189-c56337846b2e": {
    "rune": { "r": 200, "g": 60, "b": 255, "intensity": 1.5 }
  },
  "12ab34cd-...": {
    "lower": { "r": 80, "g": 200, "b": 220, "intensity": 1.0 },
    "upper": { "r": 80, "g": 200, "b": 220, "intensity": 0.5 },
    "dots":  { "r": 255, "g": 255, "b": 255, "intensity": 2.0 }
  }
}
```

* Loaded on popup open via `_load_per_item_glow()`.
* Saved on popup close via `_save_per_item_glow()`.
* If `cjson` is nil, persistence is no-op and a one-time chat warning
  fires (v0.9.7 fix).

## 5. The popup UI

Floating panel anchored top-center, 600×400, no background dim. Built
lazily on first `open_for(...)` call. Five widgets currently:

* `panel_bg` — semi-opaque dark rect with border
* `title` — "Glow Customizer"
* `subtitle` — shows `backend_id:` and `family:` for the active item
* `close_btn` — top-right X button
* `slider_r / slider_g / slider_b / slider_intensity` — 4 sliders for
  the rune component. Each slider has color-hinted thumb (red slider →
  reddish thumb), label on left, track in middle, value text on right.

Slider widget anatomy (`_widget_slider` in `_glow_picker.lua`):

* `hotspot` pass — explicit `style.hotspot` with size/offset matching
  the track (v0.9.7 fix)
* `text` pass — label on the left
* `rect` pass — 200×16 track
* `held` pass — `held_function` fires every frame while held; reads
  cursor X via `input_service:get("cursor")` and
  `UIInverseScaleVectorToResolution`, computes normalized 0–1 value,
  updates `content.internal_value` and `content.value`, calls
  `content.on_change(real)`
* `local_offset` pass — `offset_function` positions the thumb based on
  `internal_value`
* `rect` pass — 12×16 thumb
* `text` pass — value display on the right

Each slider's `on_change` is wired (in `_build()`) to write its component
field (`r`, `g`, `b`, or `intensity`) on `GlowPicker._current_glow_state.rune`,
then call `GlowPicker._live_preview()` which updates
`mod._per_item_glow_runtime` and calls `mod._reapply_glow_on_wielded()`.

## 6. Why per-item paints precedence over global

Per the user's design: the popup is "always available regardless of
toggle." The global glow override toggle is for the legacy preset-based
system; the popup is per-instance customization that should work even
when the global is off.

In `_apply_glow_to_unit`, the per-item check happens BEFORE the
`if not _glow_override_enabled then return end` gate (L3081). If a
per-item rune override exists with intensity > 0, it applies AND returns
— the global preset doesn't also paint that channel.

If the per-item check doesn't match (no override for that backend_id),
control falls through to the existing global preset logic. So users with
no per-item customizations still see the global preset behavior.

## 7. Known limitations & quirks

### a. Magic family not yet wired (M3)

`_apply_glow_to_unit` only handles `pi.rune`. For magic family weapons
(`_magic_01` / `_magic_02`), the per-item path skips and falls through
to global preset. The user perceives this as "the popup does nothing for
Weavebound weapons" because the rune block doesn't apply and there's no
magic-family equivalent yet.

### b. Popup is global, not contextual

Today `/glow_picker` is a chat command. User has to manually invoke it
after equipping the item they want to customize. M3 will auto-open the
popup when entering a cosmetic screen with a glow-capable weapon, AND
hide the popup when the item doesn't support glow.

### c. Toggle off is implicit

There's no "Glow disabled" state. Intensity = 0 effectively disables
because the apply early-returns when intensity ≤ 0, falling through to
the global path. But there's no UI affordance for "I want no glow at
all, no matter what."

### d. Cross-slot inheritance

When you customize the main weapon's rune glow, the shield in the offhand
slot DOES NOT receive the same glow automatically. They're separately
keyed by their own backend_ids. M3 will look up cousin items in the same
"glow family" and propagate.

### e. Weavebound + LA reversion

User-reported regression: when a Weavebound (magic family) weapon is in
the primary slot, the LA shield skin reverts to vanilla. Subagent
hypothesis (not confirmed yet): Weavebound's mesh path has the
`_magic_01` / `_magic_02` suffix; the LA offhand auto-selection logic
matches against the BASE vanilla path (no suffix) so it fails to find a
compatible LA variant, falls back to vanilla. Needs in-game reproduction
+ log inspection to confirm.

### f. Bretonian scroll-vs-no-scroll shield variants

User-reported gap: LA has both scroll-bearing and non-scroll Bretonian
shield meshes. Subagent finding: both variants ARE wired through the
offhand picker if they exist in LA's `SKIN_LIST` (filtered by
`swap_hand == "left_hand_unit"`). If user only sees no-scroll versions,
they're not in LA's exported list OR they're filtered by
`_is_supported_variant` (custom mesh path failed `Application.can_get`
at registration time). Needs `/la_offhand_dump` (or similar) and a
visual scan.

### g. Coop sync of per-item glow

Today per-item glow is local-only. Other players see their own global
preset on YOUR weapon, not your custom RGB. The `cos_glow_apply` RPC
that already syncs global glow can be extended to carry per-backend_id
overrides, but this is M3+ work and requires careful handling of
peer-relative backend_id resolution.

## 8. Adding the magic family (M3 roadmap)

In rough order of implementation:

1. **Extend `_apply_glow_to_unit`** — add branches mirroring the rune
   path for `pi.lower` / `pi.upper` / `pi.dots`. Each writes to its
   two-variable pair (or one variable for dots) with the same
   `native_brightness * intensity / 255` scaling.

2. **Detect family at popup open** — `GlowPicker.classify(slot_data)`
   already returns `"rune"` / `"magic"` / `nil`. Use it to decide which
   slider sections to show.

3. **Add scenegraph nodes for magic-family sliders** — 12 sliders
   stacked under 3 component sections (Lower / Upper / Dots), each with
   a label header above its R/G/B/intensity row.

4. **Conditional widget build** — `_build()` now constructs all 16 max
   slider widgets but only adds the active family's set to
   `GlowPicker._widgets` (the draw list). Magic family swaps in 12,
   rune family swaps in 4.

5. **Per-component `on_change` wiring** — each slider's callback writes
   to the correct component on `_current_glow_state.{rune,lower,upper,dots}`.

6. **Persisted state schema** — already supports the multi-component
   shape; just need to read/write `pi.lower / pi.upper / pi.dots` keys.

7. **Auto-open + auto-close** — hook the cosmetic screen entry / exit;
   detect the equipped item's family via mesh suffix; open if glow,
   close if not.

8. **Hide vanilla cousins** — for each glow item, identify its vanilla
   cousin (`x_runed_01 → x` base mapping) and filter the cosmetic menu
   to hide cousins when a glow version is also unlocked. This needs
   in-game verification per family before deploying broadly.

9. **Cross-slot inheritance** — when main weapon's glow changes, look up
   the equipped shield's backend_id and propagate the same RGB+intensity
   if the shield's mesh supports compatible glow vars.

10. **Coop broadcast** — extend `cos_glow_apply` to carry per-item
    overrides keyed by wearer_peer + backend_id.

## 9. Adding new glow shader variables (future-proofing)

If a future DLC introduces a new glow component, register it in
`_GLOW_VAR_BRIGHTNESS`:

```lua
_GLOW_VAR_BRIGHTNESS["new_glow_var"] = {
    brightness = <probed_native_value>,
    setting    = "glow_mult_<key>",
    group      = "<lower|upper|dots|rune|new_component>",
}
```

If it's a new component (not folding into existing lower/upper/dots),
also add it to `_GLOW_GROUP_COLOR_SETTING` and add a popup section.

## 10. Diagnostic commands

* `/glow_picker` — opens the popup
* `/glow_picker_close` — force-close (if it gets stuck)
* `/dump glow_state` — (if/when added) dumps `mod._per_item_glow_runtime`
* Log lines to grep for:
  * `[glow_picker] opened for backend_id=...`
  * `[glow_picker] persisted state for backend_id=...`
  * `[glow_picker] cjson global is nil` — persistence disabled

## 11. Forensic tips

If a user reports "glow doesn't work for weapon X":

1. Grep their log for `[GLOW]` lines — confirms the apply hook fired.
2. Check `[glow_picker]` lines — popup state.
3. Check the equipped item's mesh suffix — `_runed_01` or `_magic_0[12]`
   confirms it's glow-capable.
4. Run `/probe_glow_units` (if added) to dump the current wielded
   weapon's shader variable state.
5. Confirm `glow_per_item` VMF setting contents — the persistence layer.

---

## 12. Engine reference — VT2 MaterialSettingsTemplates pipeline

### Architecture

Weapon glow colour is applied at spawn time via the `MaterialSettingsTemplates` system:

- **Pipeline**: `scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua`
  - Item data has a string field `material_settings_name`.
  - `GearUtils.spawn_inventory_unit` (line 155) spawns 1P+3P units.
  - `GearUtils.apply_material_settings` (line 107) reads `MaterialSettingsTemplates[name]` and pushes each variable into `Unit.set_*_for_materials`.
- **Templates table**: `MaterialSettingsTemplates` global, populated by 4 require'd files:
  - `scripts/settings/equipment/weapon_material_settings_templates.lua` — the 6 weapon glows below
  - `scripts/settings/equipment/skin_material_settings_templates.lua` — character-skin tints (`ektrik`, `kreepus`, `krizzor` — Bardin Outlander variants etc.)
  - `scripts/settings/equipment/cosmetic_material_settings_templates.lua` — portrait frame textures
  - `scripts/settings/equipment/pickup_material_settings_templates.lua` — pickup unit settings
- **Shader variable types** (handled by `apply_material_settings`): `color`, `matrix4x4`, `scalar`, `vector2`, `vector3`, `vector4`, `texture` — silent no-op if the unit's material lacks the variable.
- **Hookable for overrides**: confirmed by the `NoGlow` mod, which hooks both `spawn_inventory_unit` (to inject empty material_settings) and `apply_material_settings` (to override `rune_emissive_color = {0,0,0}`).

### The 7 known templates

Values are HDR/overbright (>1) — that's what produces bloom. RGB clamp ~10/channel for sane custom values.

| Template | RGB | Variable | Display-name pattern | In-game source |
|---|---|---|---|---|
| `purple_glow` | (3, 1, 9) | `rune_emissive_color` | **Mixed**: 67 unique names — base "Aldthrund/Bjuna's Reaper/Asrai's Reach", "Grand Theogonist's X", "Priest's X", "Steamsmith's X", "Brockmann's Duty", + WoM Athanor weapons with "Weave"-themed descriptions | Veteran exotics, multiple events, WoM Athanor — catch-all purple |
| `golden_glow` | (8, 5, 1.5) | `rune_emissive_color` | "Myrmidia's X of the Dawn" | Geheimnisnacht 2021 (dawn theme) |
| `deep_crimson` | (7, 0, 0.1) | `rune_emissive_color` | "Crimson X" + "Zanthrund" | Skulls 2023 (Khorne) |
| `life_green` | (7, 9, 0.1) | `rune_emissive_color` | "Eternos-Ichor X" | GOTWF (Sister of the Thorn) |
| `lileath` | (5.8, 6.3, 9) | `rune_emissive_color` | "X of Bitter Dreams" | Morris 2025 (CW Lileath) |
| `versus` | 5-channel HDR | `color_glow_high/low`, `color_smoke_high/low`, `color_dots` | "Shyish-Infused X" | Versus rewards (Wind of Death) |
| `white_glow` | **NOT REGISTERED** | (template missing) | 1 referrer ("Nornaz" `_white` CW deus variant) — see "white_glow referrer" below | Abandoned/incomplete feature; renders as no-template fallback |

`versus` channels: `color_glow_high=(2.5,2,4)`, `color_glow_low=(0.7,0.3,1)`, `color_smoke_high=(0.06,0.15,0.22)`, `color_smoke_low=(0.06,0.03,0.03)`, `color_dots=(8.35,3.5,7)`.

### Visual-appearance corrections (verified vs unverified)

Only the RGB values above are verified directly. The in-game appearance was NOT extrapolated from the RGB tables alone — the following corrections were confirmed by the user from in-game observation, contradicting earlier guesses:

- **Weavebound** (`magic`-rarity Winds-of-Magic Athanor weapon line): **gold-and-blue gradient with a more complex effect than ordinary glowy skins** — NOT cyan/turquoise. (An earlier wrong description came from extrapolating the {0,211,178} cyan value from a UI loot-glow table, unrelated to the in-mesh shader.)
- **Lileath** template (`_runed_06`): renders as **WHITE** in-game, not blue/cyan/lavender. (RGB {5.8, 6.3, 9} — earlier extrapolation of "Blue" was wrong.)
- **Stylish** (`_runed_01`, no template) AND **Winds-of-Magic Weavebound** (`magic` rarity, `_magic_01` mesh): both use **a different kind of glow that is ANIMATED and baked into the model differently**. They are NOT template-driven via `rune_emissive_color` — controlling them required separate probes (see "Channel role mapping" below).

### Channel role mapping (verified empirically on Weavebound Bret longsword)

- `color_glow_high` (50) + `color_glow_low` (51) drive the LOWER part of the gradient
- `color_smoke_high` (52) + `color_smoke_low` (53) drive the UPPER part of the gradient
- `color_dots` (54) is minimal/unclear visible contribution (probably the small particle dots; minor colour)

For a uniform recolour: set the 4 main channels (glow_high/low + smoke_high/low) to the user RGB; `color_dots` can be left alone.

### Item-side reference

- **Iteration target**: `WeaponSkins.skins[skin_key] = {display_name, description, material_settings_name, rarity, inventory_icon, right_hand_unit, left_hand_unit, ...}`
- **Skin-key suffix → template family** (verified empirically — every key with the suffix has the template, no exceptions in the dumped 292):

| Key suffix | Template | Total | Display-name pattern | Source |
|---|---|---|---|---|
| `_runed_01` | none (no `material_settings_name`) | 160 | varied | "Stylish" baseline (e.g. "Goldgather", "Scarloc's Longbow") |
| `_runed_02` | `purple_glow` | 83 | varied | "Weave-Forged" pair (e.g. "The Sword of Peace", "Asrai's Reach") |
| `_runed_03` | `golden_glow` | 26 | "Myrmidia's X of the Dawn" | Geheimnisnacht 2021 |
| `_runed_04` | `deep_crimson` | 15 | "Crimson X" | Skulls 2023 (Khorne) |
| `_runed_05` | `life_green` | 30 | "Eternos-Ichor X" | GOTWF (Sister of the Thorn) |
| `_runed_06` | `lileath` | 54 | "X of Bitter Dreams" | Morris 2025 (CW Lileath) |
| `_magic_02` | `versus` | 83 | "Shyish-Infused X" | Versus rewards (Wind of Death) |
| `_runed_02_white` | `white_glow` | 1 | "Nornaz" | Single CW deus variant — template unregistered |

- **`_runed_01` ↔ `_runed_02` are DIFFERENT NAMED ITEMS**, not visual variants of one item. They share the same underlying `_runed_01` unit model — the only engine-level difference is the runtime material override. Same data confirmed for ~30 sampled pairs.
- **Source code reference for `white_glow`**: `scripts/settings/equipment/weapon_skins_morris.lua:12` has `material_settings_name = "white_glow"`. Despite the template not being registered, the engine fails silently — `apply_material_settings` lookup returns nil and iteration over nil silently no-ops in this build.
- **Skin key prefixes**:
  - `deus_*` — Chaos Wastes deus shop / Athanor variants
  - `cwv_*` — character_weapon_variants mod skins
  - `we_*` / `es_*` / `wh_*` / `dw_*` / `bw_*` / `bh_*` — character career prefix
- **Name collision warning**: `display_name` is NOT unique across `WeaponSkins.skins`. "Nornaz" exists in TWO entries (purple_glow Nornaz and white_glow Nornaz). Use the skin key (table key) as the canonical identifier in cosmetics_tweaker UI, not the localized name.

### Rarity → UI label mapping

Resolved from `Localize("rarity_display_name_<rarity>")` in-game (`/dump_skin_rarities`):

| Code rarity | UI label | Skin count | Has templates? |
|---|---|---|---|
| `plentiful` | "Plentiful" | 64 | No |
| `common` | "Common" | 75 | No |
| `rare` | "Rare" | 164 | No |
| `magic` | (unloc — `<rarity_display_name_magic>`) | 87 | No |
| `exotic` | "Exotic" | 152 | No |
| `unique` | **"Veteran"** | 452 | **Yes — 292 with, 160 without** |
| `event` | "Event" | 0 in skins (referenced in RaritySettings only) | — |
| `promo` | (unloc) | 16 | No |
| `default` | (unloc) | 3 | No |

**Total: 1013 weapon skins, 8 distinct rarities present in `WeaponSkins.skins`.**

`unique` is the ONLY rarity that uses any `material_settings_name` template. Math: 292 with_template (includes white_glow=1) + 160 without_template = 452 total Veteran skins.

### What "Veteran", "Weave-Forged", "Stylish" actually mean

- **"Veteran"** = `rarity == "unique"`. All 452 top-tier skins fall under this label in-game.
- **"Weave-Forged" and "Stylish" are NOT localized rarity-display names.** Probed `rarity_display_name_weave_forged` and `_stylish` directly — both return the bracketed key fallback (no localization entry exists). These terms are **community/colloquial**, not engine labels.
- **The actual engine split** within `unique`-rarity skins is:
  - **160 without** `material_settings_name` → no emissive override → baked unit emission only ("Stylish" colloquially)
  - **292 with** `material_settings_name` → glow template applied ("Weave-Forged" colloquially)
- **`_runed_01` ↔ `_runed_02` pairs are TWO DISTINCT NAMED ITEMS** sharing the same underlying `_runed_01` model unit. Examples (verified, all rarity=unique, same unit path):
  - "Goldgather" (no tpl) ↔ "The Sword of Peace" (purple_glow)
  - "Initiate's Flail & Shield" ↔ "Priest's Flail & Shield"
  - "Rod of Resplendent Ruin" ↔ "The Conflagrator"
  - "Deathbringer" ↔ "The Nuln Reaper"
  - "Scarloc's Longbow" ↔ "Asrai's Reach"

**Implication:** since both items in a pair use the SAME `_runed_01` unit, the only visual difference is the material_settings override. We can let users take any `_runed_01` Veteran skin and apply ANY of the 6 registered templates to it — purely through `apply_material_settings` overrides, no asset work required.

### `white_glow` referrer (resolved)

- **Single referrer**: skin key `deus_dw_1h_axe_skin_06_runed_02_white`, display name "Nornaz", `rarity=unique`, unit `wpn_dw_axe_03_t2/wpn_dw_axe_03_t2_runed_01`. A Chaos Wastes deus variant.
- A **regular** Nornaz also exists with `material_settings_name=purple_glow` — same name, same unit, but no `_white` suffix in the key. So the `_white` variant was clearly built as a "white-glow alternate of Nornaz" but the engine never registered the template. Could be revived by registering `MaterialSettingsTemplates.white_glow = { rune_emissive_color = { type="vector3", x=10, y=10, z=10 } }`.

### `magic` rarity vs `_magic_02` — NOT the same thing

Two distinct systems both use "magic" in their identifier; do not conflate them.

**`magic` rarity (~87 skins, no MaterialSettingsTemplate)** — mesh suffix `_magic_01`. **No `material_settings_name`** — the magic-glow visual (animated swirl, dispersion, particle UVs) is **baked into the mesh's bound material file** as a custom shader, not a tunable template. The 5 rune-emissive templates only override `rune_emissive_color`, which the magic shader doesn't expose. `_magic_01` shield materials do NOT expose `texture_map_c0ba2942` (the standard shield diffuse slot LA paint targets) — confirmed empirically against `es_sword_shield_breton_skin_04_magic_01_magic_01` on user's Bret weapon at v0.7.99: `Material.set_texture` returns `ok=true` but no pixel changes. Every LA option visually identical to the equipped magic shield.

**`_magic_02` suffix → `versus` template (different system, also 83 skins)** — Wind of Death / Shyish-Infused Versus rewards. Use a MaterialSettingsTemplate (`versus`) with 5-channel HDR parameters, applied via the standard `apply_material_settings` path. Rarity is `unique`, not `magic`.

### Compatibility matrix for LA-style diffuse paint

| Mesh family | Standard diffuse slot exposed? | Tintable via templates? | LA paint visible? |
|---|---|---|---|
| Standard (e.g. `wpn_emp_gk_shield_02`) | Yes | No (no `rune_emissive_color`) | Yes |
| Runed (`*_runed_01`) | Yes | Yes (5 colors) | Yes |
| Magic-rarity (`*_magic_01`) | **No** | **No** | **No** — silent no-op |
| Versus (`*_magic_02`) | Untested for shields | Yes (`versus` template) | Untested |

### "Separate glow from model" architecture (viable scope)

User concept: let players pick any base shield mesh, any heraldic, and any glow colour independently of the equipped illusion.

- **Viable substrate**: `*_runed_01`-family meshes. They expose BOTH the standard diffuse slot (`texture_map_c0ba2942` — paintable by LA-style heraldic textures) AND `rune_emissive_color` (tunable by any of the 5 rune-emissive templates).
- **Glow palette achievable**: `none` (default) / `purple_glow` / `golden_glow` / `deep_crimson` / `life_green` / `lileath` / `versus` (if material variables match — has 5 channels, may need testing on shield meshes).
- **Glow palette NOT achievable from a runed substrate**: the `_magic_01` rarity-magic shader's animated swirl + dispersion. That effect is locked to its native `_magic_01` mesh+material pair — no template can recreate it on a different mesh.
- **Implementation path** (when/if user wants this): hook `GearUtils.spawn_inventory_unit` (per the NoGlow mod pattern) to inject the user-chosen `material_settings` into the spawn args, bypassing the skin's authored `material_settings_name`.

### Template-mutation vs post-call overlay (the v0.8.16 fix)

**VERIFIED working pattern**: TEMPLATE MUTATION, not post-call overlay. Three copies of `apply_material_settings` exist in VT2 (`GearUtils.apply_material_settings`, the global `_G.apply_material_settings` at `flow_callbacks_foundation.lua:896`, `CosmeticUtils.apply_material_settings`). Hook each via `mod:hook` (NOT hook_safe) and inside the wrapper:
1. Look up `MaterialSettingsTemplates[material_settings_name]`.
2. Save the original `x/y/z` of each variable to override.
3. Mutate the template entries' `x/y/z` to your preset values.
4. Call `func(unit, material_settings_name)` — vanilla reads the template and applies your values via its own `Unit.set_vector3_for_materials` calls.
5. Restore the original `x/y/z`.

**Why this works and post-call overlay didn't:** empirical test — `mod:hook_safe` overlay using `Unit.set_vector3_for_materials` after vanilla returned painted 3p reliably but NEVER visually affected 1p, even though every call returned `ok=true` (verified via `[GLOW-trace]` diagnostic in v0.8.5). Vanilla's own writes via the same API DO paint 1p. Some engine-internal mechanism rejects our second write on the 1p unit but accepts vanilla's. Mutating the template makes vanilla itself the only writer, sidestepping the issue. NoGlow uses the same template-mutation trick.

**Activation requirement:** the override only paints on fresh weapon spawns (the moment vanilla calls `apply_material_settings`). Toggling on/off or switching presets does NOT live-repaint already-spawned weapons — the user must re-apply a cosmetic / re-equip via inventory loadout to trigger a respawn. v0.8.7-v0.8.9 attempted live re-paint by walking inventory_system slots; that destabilised adjacent unit state (hand meshes vanished on inspect, 1P state broke), so it was reverted in v0.8.10. Safer next-attempt approach: hook the wield event and paint only at the moment a unit becomes visible, never touching sheathed units.

**Override doesn't paint skins without `material_settings_name`:** confirmed empirically v0.8.4 — Stylish (`_runed_01`) items don't take the override because vanilla never calls `apply_material_settings` on them. The v0.8.16+ fix mechanism handles this via custom-template injection at `GearUtils.spawn_inventory_unit` (see top of GLOW_SYSTEM.md sections 1-11).

### Adding glow to weapons that don't have it

**Not possible from Lua alone** with the current toolkit. The shader uniforms (`rune_emissive_color`, `color_glow_*`, `color_smoke_*`, `color_dots`) only produce visible output if the weapon's MATERIAL exposes them — and that's defined in the `.unit`/`.material` asset, not at runtime. `Unit.set_vector3_for_materials` on a non-glow weapon silently no-ops (verified empirically via `/glow_scan`).

**Practical path:** each weapon family already has a `_runed_01` Stylish mesh variant (the loot-chest white-glow variants — vanilla skin item, every Veteran weapon has one). To add glow to a vanilla-looking weapon, the user can equip its `_runed_01` Stylish illusion via Okri's apply-illusion (or our modded-realm bypass) and then colour it via the override. A custom-illusion route through `cosmetics_tweaker._register_custom_illusions` could surface a "Make Glowy" toggle that swaps to the matching `_runed_01` mesh path.

### Stingray Vector3 lifetime gotcha

`Vector3(x, y, z)` is **frame-allocated**; do NOT cache the result as a module-level constant. Across frames the storage is invalid and `pcall(Unit.set_vector3_for_materials, unit, name, cached_vec)` returns false. Construct fresh per call. v0.8.20 had this bug — every scan reported `painted=0` on every candidate. Fixed in v0.8.22 by `local function _probe_red() return Vector3(15, 0, 0) end`.

### Tooling notes

- **In-game dump commands** (log tags `[DUMP:glows]`, `[DUMP:rarity]`, `[DUMP:names]`):
  - `/dump_glows` (v0.7.78-dev) — iterates `WeaponSkins.skins`, groups by `material_settings_name`, dumps RGB + per-skin display name, description, rarity, icon, unit paths.
  - `/dump_skin_rarities` (v0.7.82-dev) — dumps all rarity → localization labels, groups every skin by rarity, separates `with_template` / `without_template`, dumps the white_glow referrer, and samples `_runed_01` ↔ `_runed_02` sibling pairs side-by-side.
  - `/dump_all_names` (v0.7.85-dev) — emits `skin_key|name|desc|rarity|tpl` for every entry in `WeaponSkins.skins`, with per-100-line flushing.
- **Truncation issue (FIXED):** dumping ~290 lines via `mod:info` in a single frame caused line-drop in the engine log buffer (291 headers, only 255 SKIN lines emitted on first run). Fix that worked: call `_flush_log()` between every dump section.
- **Disabling all glows:** hook `apply_material_settings` and zero `rune_emissive_color` (covers 5/7 templates: purple/golden/crimson/life/lileath) PLUS the 5 `versus` channels (covers versus). The `white_glow` template doesn't currently apply anything (unregistered) so it needs no override. NoGlow only handles `rune_emissive_color`, so versus skins still glow under it.

### In-repo full catalogue

**Read first**: `cosmetics_tweaker/VETERAN_SKIN_CATALOG.md` — full per-template skin tables (display name + skin key + unit paths + source file) for every vanilla weapon skin. Generated from VT2 source + cross-referenced against in-game dump output. Regenerate with `py cosmetics_tweaker/_build_skin_catalog.py`.

The catalogue covers vanilla skins only (~891). Mod-injected entries (cosmetics_tweaker custom illusions, character_weapon_variants `cwv_*` weapons) bring the runtime total to ~1013 — they're NOT in the catalogue by design.

---

*Update this doc on every change that touches the glow pipeline.*
*Stale docs are worse than no docs — see `~/.claude/CLAUDE.md § Workflow`.*
