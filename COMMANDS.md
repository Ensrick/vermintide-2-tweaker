# Mod Command Inventory

Per-mod inventory of all chat commands registered via `mod:command(...)`
across this monorepo.

Every entry is the literal first argument of `mod:command("name", ...)` —
typed in chat as `/<name>` directly (NO mod-id prefix; see CLAUDE.md "Lua
Environment" section on the chat command syntax rule).

**Snapshot date:** 2026-05-25 (lobby_tweaker retired -- its commands absorbed into gt as `/gt_lobby_*`; bt + gut / others not re-audited). Refresh after any mod adds/renames commands — grep `mod:command\(` across `**/*.lua` to
regenerate.

---

## By mod

### `wt` (weapon_tweaker)
```
info, animlog, force3p, force1p, sm_probe,
brace_to_repeater_skin, brace_to_repeater_dump,
dump, dump_actions, dump_weapons,
wt_regression_test, wt_dump_wielded,
wt_dump_anim_picks, wt_coverage,                  -- anim tuning loop (export + skeleton probe)
wt_dev_hp_apply, wt_dev_hp_reset, wt_dump_hold_pose  -- hold-pose tuner
```
*(wt section refreshed 2026-06-11 — added the 7 commands landed since the 2026-05-25 snapshot.)*

### `gt` (general_tweaker_dev)
*(2026-07-01: the `gt_` prefix was stripped from ALL gt commands to simplify. The ONLY exception is `gt_regression_test`, kept prefixed because bare `regression_test` collides with gui_tweaker's. `lobby_*` names keep their `lobby_` prefix — only `gt_` was removed.)*
```
-- Cheats / player-state:
god, no_enemies, clear_enemies, unstuck, cloak, unkillable, inndmg, noclip, ai,
infinite_ammo, stamina, gigapower, ultreset, pause, time_faster, time_slower,
-- Level control / match flow:
win, fail, restart, killbots, die, respawn, fix_sound, bottoggle, readyup, inn,
-- Bots:
no_bots, bots_in_keep,
-- Spawners:
spawncreature, nextcreature, prevcreature, destroycreatures, savecreature, selectedcreatures,
spawnitem, nextitem, previtem,
-- Saved positions (per-map teleport, #306):
save_position_1 .. save_position_10, recall_position_1 .. recall_position_10,
-- Dumps / debug:
dump_settings, dump_level, dump_glossary, dump_cosmetics, dump_items_by_slot,
dump_hero_view, dump_ai, dump_menu, ai_slotdump, bot_loadout_dump, fire_probe,
gt_regression_test,   -- ONLY command still carrying the gt_ prefix
-- Host-side lobby controls (absorbed from lobby_tweaker; still lobby_-prefixed):
lobby_reserve, lobby_unreserve, lobby_reservations,
lobby_ignore, lobby_ignore_persist, lobby_unignore, lobby_ignored, lobby_ignore_last,
lobby_idle_whitelist, lobby_idle_unwhitelist, lobby_idle_status,
lobby_motd_test, lobby_motd_set, lobby_motd_clear,
lobby_manifest_dump, lobby_manifest_probe
```

### `gut` (gui_tweaker)
```
gut_save_loadout, gut_load_loadout, gut_list_loadouts,
gut_edit_hud, gut_reset_hud, gut_list_hud,
gut_hud, gut_hud_cycle,
gut_inv,                       -- open inventory mid-mission (migrated from gt /gt_inv 2026-06-24)
gut_hero_select,               -- open HeroView talents layout mid-mission (live-safe; career PICK stays keep-only by design)
reset_modded_loadouts,         -- wipe the modded loadout store (optional career arg) -> re-seed from official (native loadouts #175)
gut_loadout_status,            -- dump the modded loadout store state to chat + console (native loadouts #375 diagnostic)
scrub_official_loadouts,       -- repair modded/dangling weapon+frame ids in OFFICIAL loadouts (#402; 'apply' to write, default report-only)
gut_regression_test, gut_lua_mem
```
*(partial gut audit added 2026-06-24 alongside the in-mission inventory migration; gut was previously un-audited in this file — other gut commands may exist.)*

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
cwv_despawn_probes, cwv_give, cwv_give_javelin
```

### `cim` (crafting_in_modded)
```
amulet_n, amulet_c, amulet_t, forge_dump, forge_dump_props,
forge_dump_backend, craft_dump, forge, forge_trait, forge_props,
forge_skin, forge_power, forge_cancel, forge_confirm, salvage_debug,
forge_list, forge_delete, inv_dump, mirror_dump, craft_recent
```

### `enemy` (enemy_tweaker)
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

### `bt` (buff_tweaker)

**(RETIRED 2026-06 — bt archived to `_archive/buff_tweaker_v0.1.12-alpha/`; these commands no longer register. `get_mod("bt")` is always nil. Block kept for historical reference.)**

```
bt_net_replay, perf_dump, bug_report, bt_regression_test
```

`bug_report` was a zero-arg paste-ready context dump (loaded mods + version + non-default settings + career/level + log-path pointer) intended for handoff to a Claude agent on a bug report. Mirrored output to both chat and `console_logs/`.

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
