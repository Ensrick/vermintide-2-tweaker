# Material-Hijack (patched) — Changelog

## v0.1.2 (2026-05-18)

### Fixed: conflict-guard chat-warning text flipped the wrong way

v0.1.1's chat warning told users "keep this patched version" when both forks were enabled, but that recommendation is wrong in any setup that includes Loremaster's Armoury or another mod that calls `get_mod("Material-Hijack")` at runtime. Those downstream mods key off the original's `mod_id` ("Material-Hijack") — they don't see this fork's `mod_id` ("material_hijack_patched"). So disabling the original silently breaks LA's custom-mesh / custom-texture features even though the patched fork is technically more defensive.

Hook-registration behavior is unchanged from v0.1.1 — when both forks are enabled, this fork still skips registering its hooks so the original alone handles equip/visibility/spawn events (preventing the NVIDIA shader-cache deadlock documented in v0.1.1). Only the chat-warning text changed: it now tells the user to **disable this patched fork** (NOT the original) if they use any mod that needs `get_mod("Material-Hijack")` to resolve. The fork is only beneficial in setups without those dependents.

Workshop description (`itemV2.cfg`) updated to match. Burned from the realization that LA depends on the original's mod_id and so the fork can't supersede it in practice.

## v0.1.1 (2026-05-18)

### Fixed: conflict guard — if the original Material-Hijack is also enabled, skip hook registration

The original Material-Hijack (Workshop `2771980886`) and this fork hook the SAME six functions (`Unit.set_unit_visibility` / `Unit.set_visibility` / `Unit.set_mesh_visibility`, `GearUtils.create_equipment`, `UnitSpawner.spawn_local_unit`, `HeroPreviewer._spawn_item_unit`). Per VMF's hook-chaining model both hooks run, so every unit spawn / visibility change / equip event processes the same unit TWICE. `replace_textures` runs twice on the same mesh, sync-loading the same skin package multiple times and leaving material slots pointing at orphan material IDs after the second pass.

On NVIDIA hardware the renderer then can't resolve those materials (`[MeshObject] Failed looking up material: '#ID[...]' in material manager`), thrashes `D3D12 CreateGraphicsPipelineState`, and deadlocks the renderer thread in the NVIDIA shader-cache thunk (`NvMemMapStoragex::TotalDiskUsage`). Burned: amand's session 2026-05-19 (session `2724b4bf-1c14-40f6-98ed-151b3dda41b5`) — 16.1 s renderer freeze on Keep load after 3 cycles of breton (Grail Knight) skin material warnings on her VRAM-constrained RTX 4050 Laptop. AMD users (lynnd) degraded visually without deadlocking because AMD's D3D12 driver has no equivalent of `NvMemMapStoragex`; VRAM-headroom-rich NVIDIA setups escaped on luck.

v0.1.1 detects the original at module-load via `get_mod("Material-Hijack"):is_enabled()` and, if it returns true, skips registering any of our hooks and prints a chat warning telling the user to disable the original. The conservative choice — letting the original handle everything when both are enabled — sidesteps the double-hook completely. Users should disable the original (Grundlid, 2023-06-06) and keep this patched fork; the fork is a strict superset (same six hooks + defensive `Application.can_get` gates on package / unit loads).

Load-order note: VMF initializes mods in ascending workshop_id, so the original (2771980886) loads before this fork (3727311798); the conflict check at our module-load reliably sees the original's handle.

## v0.1.0 (2026-05-16)

Forked from Grundlid's Material-Hijack v? (Workshop 2771980886). Sourced from the decompiled bundle.

### Why this fork exists

`[Script Error]: Unit not found #ID[...]` fatals were tracking back through Material-Hijack's hook frame because Material-Hijack reimplements `UnitSpawner.spawn_local_unit` inline — it calls `World.spawn_unit` directly with whatever unit_name the caller passed in. If that name isn't in the resource manager (e.g. a bot's saved loadout references a missing skin's 3P unit), the C-level assert in `c_api_world.cpp:67` fatals before any Lua-side guard can run.

### Patches

1. **`UnitSpawner.spawn_local_unit` hook** — pre-validate `unit_name` via `Application.can_get("unit", unit_name)` before calling `World.spawn_unit`. If missing, log + return nil instead of fataling. The caller (`spawn_local_unit_with_extensions`) is itself fragile against nil, so we additionally try `func(self, unit_name, ...)` to give the next hook / vanilla a chance — if vanilla would also fatal, we've at least logged the offending unit name.
2. **`replace_textures`** — wrap `Managers.package:load` in `Application.can_get("package", ...)` so a unit with a stale `mat_to_use` field referencing a removed package doesn't queue a phantom load.
3. **`add_particles`** — same: pre-validate `Application.can_get("package", pkg)` before load.
4. **`replace_textures` / `add_particles` entry guard** — return early if `unit` arg is nil or not alive. Original code crashed if `unit_1p` or `unit_3p` were nil entering `GearUtils.create_equipment` hook.

### Behaviour unchanged

- All six hooks ported as-is otherwise (`Unit.set_unit_visibility`, `Unit.set_visibility`, `Unit.set_mesh_visibility`, `GearUtils.create_equipment`, `UnitSpawner.spawn_local_unit`, `HeroPreviewer._spawn_item_unit`).
- `AnimTextureExtension` class ported byte-for-byte from the decompile.
- Mod ID changed from `Material-Hijack` to `material_hijack_patched` so the two can coexist while you test (disable the original before enabling this one).

### Not shipped

- The original mod's fallback texture assets (`textures/default_col`, `textures/default_emis`, `textures/T_Texture_MOS`, `textures/T_Texture_NR`, etc.). If a unit's material slot ends up pointing at one of these short paths, the texture set will silently fail rather than show the fallback. Visual-only consequence; doesn't crash. Add the textures here later if needed for full feature parity with custom-cosmetic mods that depend on them.
