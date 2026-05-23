# Phase B — In-Context Popup Glow Picker (Design)

Status: **design, unimplemented**. Phase A (per-component RGB+intensity sliders in the Settings tree) shipped in v0.9.1-dev. Phase B layers the in-context popup on top of the same VMF settings; no schema change required.

## Goal

A popup that opens from the cosmetic-changing screen (HeroWindowCosmeticsLoadout) when the player selects a glow-eligible item. The popup shows R/G/B/intensity sliders only for the visual components that apply to the equipped item's mesh family. **Available regardless of any master toggle — the popup IS the customizer, and it supersedes the existing VMF glow override entirely.** Persistence is **per-item-instance (keyed by `backend_id`)** stored as a single JSON-blob VMF setting `glow_per_item`.

## Scope correction (2026-05-20)

An earlier draft of this doc included a "Phase A" step that added VMF settings-tree RGB+intensity widgets for per-visual-group customization. User clarified that's the wrong surface — VMF is for global cross-mod options, the popup IS the per-item glow customizer. Phase A was reverted. The popup is now the only path forward (no VMF additions beyond the existing v0.9.0 preset dropdowns, which remain as fallback until the popup fully supersedes them).

## Context-detection rules (already implementable in Lua)

Given a wielded slot's `slot_data.skin` (string key into `WeaponSkins.skins`) and the equipped unit's `right_unit_3p` / `left_unit_3p` path, classify the item:

| Suffix pattern on skin / unit path | Family             | Components shown                  |
|------------------------------------|--------------------|-----------------------------------|
| `_runed_01`                        | Stylish baseline   | Rune only                         |
| `_runed_02..06`                    | Themed Veteran     | Rune only                         |
| `_magic_01`                        | Weavebound         | Lower + Upper + Dots              |
| `_magic_02`                        | Shyish-Infused     | Lower + Upper + Dots              |
| no suffix match                    | non-glow weapon    | popup not offered                 |

If the user is wielding a sword+shield, run classification on EACH hand independently; if either side is glow-eligible, offer the popup with the relevant side's components.

## Architecture

### Settings binding

All sliders write to the existing flat-key VMF settings introduced in Phase A:

- `glow_rune_r/g/b/intensity`
- `glow_lower_r/g/b/intensity`
- `glow_upper_r/g/b/intensity`
- `glow_dots_r/g/b/intensity`
- `glow_custom_rgb_enable` (auto-set ON when user touches any popup slider)

Reads/writes via `mod:get(key)` / `mod:set(key, value)`. The `mod.on_setting_changed` hook (cosmetics_tweaker.lua:616) already broadcasts the per-peer glow state for any `glow_*` key change, so the popup's writes propagate to remote viewers for free.

### Rendering

VMF cannot create popup windows directly — must use the engine's UIRenderer. Reference implementations:

- `scripts/ui/popup/popup_manager.lua` — engine's built-in popup framework (Yes/No, text-input). Not suitable for sliders but useful to study the lifecycle.
- `scripts/ui/views/hero_view/windows/hero_window_cosmetics_loadout.lua` — the host window we're injecting into. Study its `_create_ui_elements`, `_update`, and `_render` methods for the scenegraph pattern to mirror.
- `Vermintide-Mods/CrosshairCustomization` — has 0-255 numeric VMF inputs (sliders in spirit). Not popup-shaped, but the option layout is the closest existing reference.

### Hook points

```lua
mod:hook_safe("HeroWindowCosmeticsLoadout", "on_enter", function(self, ...)
    -- create popup widgets, attach to self._ui_scenegraph
end)

mod:hook("HeroWindowCosmeticsLoadout", "update", function(func, self, dt, t, ...)
    func(self, dt, t, ...)
    -- 1. detect equipped slot's glow family
    -- 2. update visibility of "Customize Glow" button + popup
    -- 3. drive slider mouse-drag state if popup is open
    -- 4. re-render popup widgets via self._ui_renderer
end)

mod:hook_safe("HeroWindowCosmeticsLoadout", "on_exit", function(self, ...)
    -- tear down popup widgets, persist final values
end)
```

### Slider widget (custom-drawn)

VT2's UIRenderer doesn't ship a horizontal slider. We need to roll our own:

- A 200×16 px track texture (use `texture_uv` from any flat gray UI atlas — `materials/ui/ui_1080p_common_atlas`).
- A 12×16 thumb texture (any small button atlas reference).
- Mouse hit-test on mouse-down: compute thumb position from current value (0-255 mapped to track width).
- Drag updates `mod:set("glow_xxx_r", new_value)` continuously.
- A small numeric label to the right showing the current value.

Pattern to copy: `scripts/ui/views/cutscene_loop_ui.lua` or `scripts/ui/views/end_view/end_view.lua` both have custom interactive widgets that mod authors have replicated successfully.

### Live-repaint caveat

Per `reference_vt2_weapon_glow_system.md` and the v0.8.10 reversion, walking spawned units to re-apply the glow live destabilizes 1P unit state. The popup MUST NOT trigger a live walk. Two safe options:

1. **Best-effort re-wield**: after popup closes, programmatically wield the same slot the player was on (`SimpleInventoryExtension:wield(slot_name)`). The wield triggers fresh `apply_material_settings` calls via the existing template-mutation hook. This is the same pattern users do manually today.
2. **Visible-unit-only repaint**: hook `SimpleInventoryExtension.wield` (already done partially by v0.8.0x); on wield, re-call `_apply_glow_to_unit(unit)` on the just-wielded units. Safe because the unit is in a known-good state at that moment.

Option 1 is simpler and zero-risk; Option 2 is smoother UX. Try 1 first.

## Implementation milestones

1. **M1 — chat-command popup stub** (~1 session). `/glow_picker` opens a basic full-screen UIRenderer overlay with 4 panels (rune/lower/upper/dots) and 16 sliders + master toggle. No context detection yet — just proves the UI works. Persists to VMF settings. Closes on Escape / OK button.
2. **M2 — context detection** (~0.5 session). Wire up the mesh-family classifier. When opening the popup, dim/hide non-applicable component panels. Stays openable from `/glow_picker` for testing.
3. **M3 — cosmetic-screen integration** (~1 session). Inject a "Customize Glow" button into HeroWindowCosmeticsLoadout. Button visible only when equipped slot is glow-eligible. Click opens the popup with the right components shown.
4. **M4 — re-wield on close** (~0.25 session). Programmatic wield to refresh visible glow without user re-equipping.
5. **M5 — LA shield integration** (gated by `/la_shield_glow_probe` result from Phase A). If LA shields can accept glow paint, surface their glow components in the popup too. If not, popup stays vanilla-only and we document the limitation.

## Out of scope for Phase B

- HDR color preview swatch (would be a nice-to-have but the slider values are enough)
- Per-skin-key persistence (currently all weapons share the global `glow_*` values; per-skin would require a name-keyed nested dict)
- Custom material settings for non-glow weapons (asset-level work, separate effort)
