# Mod Command Inventory

Per-mod inventory of all chat commands registered via `mod:command(...)`
across this monorepo.

Every entry is the literal first argument of `mod:command("name", ...)` —
typed in chat as `/<name>` directly (NO mod-id prefix; see CLAUDE.md "Lua
Environment" section on the chat command syntax rule).

**Snapshot date:** 2026-05-19 (from cross-mod audit). Refresh after any
mod adds/renames commands — grep `mod:command\(` across `**/*.lua` to
regenerate.

---

## By mod

### `wt` (weapon_tweaker)
```
info, animlog, force3p, force1p, sm_probe,
brace_to_repeater_skin, brace_to_repeater_dump,
dump, dump_actions, dump_weapons
```

### `gt` (general_tweaker)
```
tp, freecam, noclip, dump_glossary, dump_cosmetics, unstuck, god,
no_enemies, win, fail, restart, kill_bots, die, fix_sound,
dump_items_by_slot, ai, ult_reset, time_faster, time_slower, pause,
infinite_ammo, infinite_stamina, giga_power
```

### `ct` (chaos_wastes_tweaker)
```
peers, dump_spawners, dump_potions, dump_boon_loc, dump_boons,
dump_buffs, dump_mutators, dump_traits, dump_adventure_names,
pool_status, force_inject_pool, cw_status
```

### `crt` (career_tweaker)
```
ct_status
```

### `cos` (cosmetics_tweaker)
```
flush_log, dump_glows, dump_skin_rarities, dump_all_names, check_vmf,
probe_hat, probe_cosmetics, frames_status, la_offhand_dump,
offhand_debug, glow_status, glow_trace, glow_dump, glow_probe,
glow_scan, glow_scan_stop, glow_restore, la_dump, la_trace,
la_force, la_attach, la_loadout, la_hats
```

### `cwv` (character_weapon_variants)
```
cwv, cwv_dump_javelin_impact,
cwv_om_pos_{1p_r,1p_m,3p_r,3p_m},
cwv_om_rot_{1p_r,1p_m,3p_r,3p_m},
cwv_om_rotmul_{1p_r,1p_m,3p_r,3p_m},
cwv_om_eul_{1p_r,1p_m,3p_r,3p_m},
cwv_om_scale_{1p_r,1p_m,3p_r,3p_m},
cwv_om_show, cwv_musket_ammo_diag, cwv_musket_dump,
cwv_probe_skins, cwv_probe_unit, cwv_probe_attach,
cwv_despawn_probes, cwv_give
```

### `cim` (crafting_in_modded)
```
amulet_n, amulet_c, amulet_t, forge_dump, forge_dump_props,
forge_dump_backend, craft_dump, forge, forge_trait, forge_props,
forge_skin, forge_power, forge_cancel, forge_confirm, salvage_debug,
forge_list, forge_delete, inv_dump, mirror_dump, craft_recent
```

### `et` (enemy_tweaker)
```
et_dump_breeds, et_dump_compositions, et_status
```

### `vdl` (verminious_dreams_lighting)
```
vdl_sky, vdl_sun, vdl_sun2, vdl_amb, vdl_amb_top, vdl_fog, vdl_exp,
vdl_light, vdl_light_int, vdl_torch, vdl_torch_int, vdl_torch_patterns,
vdl_lights, vdl_lights_list, vdl_clear, vdl_reset, vdl_reapply,
vdl_dump, vdl_save, vdl_level, vdl_help
```

### `mp` (modded_progression)
```
mp_dump, mp_reset
```

### `dcp` (dynamic_cosmetic_portraits)
```
portrait_diag, portrait_dump, test_portrait
```

### `event_tweaker`
```
event_probe, event_active, event_clear, event_apply
```

---

## Collisions

**As of 2026-05-19: none among active mods.** Several mods use `dump_*`
patterns but with distinct names (e.g. `dump_actions` is wt; `dump_glossary`
is gt; `dump_boons` is ct).

The legacy `tweaker` mod (mod-id `t`, frozen, unshipped through VMB)
registers `tp` / `god` / `win` / `unstuck` / `dump_boons` — would collide
with gt and ct if it were active. Per the VMB migration rule it's not
migrated; ignore unless someone re-enables it.

---

## How to apply

- Use this table to answer "is `/X` a real command, and which mod owns it?"
  without re-grepping source.
- When adding a new `mod:command(...)`, verify the name doesn't collide
  with this list. Prefer mod-ID-prefixed names for clarity when the bare
  name would be ambiguous (e.g. `cwv_*`, `forge_*`, `vdl_*`, `et_*`,
  `vdl_*`, `mp_*`, `la_*`).
- Refresh this entry after any mod adds/renames commands. Regenerate via:
  ```powershell
  Get-ChildItem -Recurse -Filter *.lua | Select-String 'mod:command\(\s*"([^"]+)"' -AllMatches `
    | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
  ```
