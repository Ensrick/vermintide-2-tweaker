# CLAUDE.md — dynamic_cosmetic_portraits

This file applies when working anywhere under
`vermintide-2-tweaker/dynamic_cosmetic_portraits/`. Read the repo-root
`CLAUDE.md` (mod table, build commands, deploy script) for cross-mod context.

## ⚠️ Adding a new portrait — DO NOT FREE-HAND THE ASSETS

**Use the script. Always.**

```powershell
.\tools\add_portrait.ps1 -SourcePng "<110x130 PNG>" -HatKey "kruber_<key>"
```

Multiple shipped versions of this mod (and its predecessor inside
`cosmetics_tweaker`) broke because an AI agent guessed at the asset
pipeline. The recurring failure modes were:

| Wrong approach | Why it breaks |
|---|---|
| Bicubic-resize 110×130 → 86×108 / 60×70, no alpha mask | RGB content fills the entire shrunk canvas; corner pixels poke past the in-game frame's hex cutout. **Visible overflow.** |
| Copy 110×130 source verbatim into all three filenames | The HUD and matchmaking widgets render the texture at their native widget size. Without an alpha mask, content still fills the rectangle. **Visible overflow.** |
| Bake a hard hex frame into the source PNG | Doubles up against the in-game frame widget that's drawn on top. **Visual mess.** |
| Use `Material.set_texture()` on Gui materials at runtime | Gui pipeline is separate; the call no-ops silently. |
| Hook `UIRenderer.create` to detect material readiness | VMF destroys+recreates the renderer in its own hook; the user-mod hook never fires. Use `Gui.material()` probe instead. |

The script encodes the only correct workflow:

1. **Medium (110×130)**: copy source verbatim, no resize, no mask.
2. **HUD (86×108)**: bicubic-resize RGB from source, then composite alpha
   from `portrait_kruber_mercenary_hat_0001.png` (Estalia HUD).
3. **Small (60×70)**: same as HUD, alpha from
   `small_portrait_kruber_mercenary_hat_0001.png`.

The alpha mask shape is identical for every portrait at a given size —
it's defined by the in-game frame widget's hex cutout, not by portrait
content. Borrowing alpha from any working portrait yields the correct mask.

After the script writes the assets, you still manually wire up:
- `dynamic_cosmetic_portraits.lua` → `_PORTRAIT_MATERIALS` + `_hat_portrait_map`
  (or `_skin_portrait_map` for outfits — see comments at those tables).
- `dynamic_cosmetic_portraits_data.lua` → `custom_gui_textures.textures`
  + `custom_gui_textures.ui_renderer_injections`.
- `resource_packages/dynamic_cosmetic_portraits/dynamic_cosmetic_portraits.package`
  → `material = [ … ]` and `texture = [ … ]` lines (3 each).
- Bump `MOD_VERSION` in the main lua.

The script's "NEXT STEPS" output reminds you of all four. See
`DEVELOPMENT.md` "Adding a new portrait" for the full step-by-step.

## Identifying the cosmetic key

Cosmetic keys (e.g. `mercenary_hat_0003`, `skin_es_default`) are opaque
identifiers from `CosmeticUtils.get_cosmetic_slot(player, "slot_hat" |
"slot_skin").item_name`. The mapping from key → in-game display name is
in `CHARACTER_COSMETIC_CATALOG.md`. **Always consult that catalog when
the user names a portrait by its in-game display name** (e.g. "Plumed
Horseshoe" → look up → `mercenary_hat_0003`).

## Build & deploy

```powershell
Set-Location "C:\Users\danjo\source\repos\vermintide-2-tweaker"
node C:/Users/danjo/source/repos/vmb/vmb.js build dynamic_cosmetic_portraits --no-workshop --cwd
.\deploy_all.ps1 -Mods @("dynamic_cosmetic_portraits")
```

`deploy_all.ps1` deploys to the local Steam Workshop folder
(`steamapps/workshop/content/552500/3721036701/`) and verifies bundle
hashes. Workshop ID **3721036701**, visibility `private`.

## Hot-reload is unsafe

`Ctrl+Shift+R` will leave dangling C++ resource locks on loaded
materials/textures. Always restart VT2 after redeploying. This applies
to every mod with non-Lua resources — see
`feedback_hot_reload_unfixable.md` (Anthropic memory).

## Diagnostic commands

Three console commands are registered (in-game chat):

| Command | Purpose |
|---|---|
| `dynamic_cosmetic_portraits portrait_diag` | State + material readiness check across every Gui handle. Reports current `career_settings.portrait_image` / `picking_image`, detected hat & skin keys, registered materials. |
| `dynamic_cosmetic_portraits portrait_dump` | Deep-walks every UI surface and dumps every widget with `character_portrait` or `portrait` in its content. Use to map which surfaces use which textures. |
| `dynamic_cosmetic_portraits test_portrait` | Force a `_sync_portrait_settings()` call and report the resulting state. |

If a user reports a portrait bug, ask them to run `portrait_diag` and
paste the output before guessing.

## Code-of-conduct for this mod's lua

- **Forward references will crash this mod.** Lua locals are not hoisted.
  When adding a function, check that all callers come AFTER its definition
  line. (History: this mod's predecessor crashed three separate sessions on
  this exact bug. See `feedback_lua_forward_reference.md` memory.)
- **`_gui_has_material()` and `_flush_log()`** are duplicated as locals
  here rather than imported from cosmetics_tweaker. Don't try to share —
  this mod is intentionally standalone.
- **Hot-reload is unfixable.** Don't add `mod.on_reload` handlers.
- **Settings are read via `mod:get("dynamic_portraits")`.** That setting
  lives in this mod, not in cosmetics_tweaker (post-split).
