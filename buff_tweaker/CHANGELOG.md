# Tweaker: Buffs Changelog

## 0.1.1-alpha (2026-05-22) — Fix latent `rawget` bug in registration helpers

bt's registration helpers had the same latent bug just caught + fixed in crt 0.3.4-dev: `if not NL.buff_templates[name]` triggers vanilla's NetworkLookup `__index` metamethod (`network_lookup.lua:2361`), which calls `error()` on any missing key. The bug hadn't fired in production because the bt master toggle defaults off — no real-world registration pass has run yet — but it would have crashed bt's master-toggle apply path the first time anyone flipped the switch.

### Fix

`_register_buff_templates`, `_register_damage_profiles` now use `rawget(t, key)` for every existence check on `BuffTemplates` / `TalentBuffTemplates[hero]` / `NetworkLookup.buff_templates` / `DamageProfileTemplates` / `NetworkLookup.damage_profiles`.

`_register_explosion_templates` and `_register_stat_buff_methods` were already safe (no NetworkLookup-backed reads).

## 0.1.0-alpha (2026-05-21)

### Initial scaffold

New shared-registry mod. Internal id `bt`, Workshop title "Tweaker: Buffs (WIP)", visibility `friends_only`.

Extracted from `weapon_tweaker` / `career_tweaker` / `enemy_tweaker`: each previously shipped a byte-identical 419-line `*_big_rebalance_registrations.lua` file plus its own master toggle. This mod now owns:

- The canonical 328-entry registration list (272 BuffTemplates + 37 NewDamageProfileTemplates + 16 ExplosionTemplates + 3 StatBuffApplicationMethods) — see `scripts/mods/buff_tweaker/buff_tweaker_registrations.lua`.
- The single master toggle `bt_master_enable_br_registrations` (default off).
- The actual idempotent `BuffTemplates` / `TalentBuffTemplates` / `NetworkLookup` / `DamageProfileTemplates` / `ExplosionTemplates` / `StatBuffApplicationMethods` writes when master is on. Triggered from `on_all_mods_loaded`, `on_game_state_changed`, and `on_setting_changed`.

Exposes one public API call for consumer mods:

```lua
local bt = get_mod("bt")
if bt and bt.is_br_active and bt:is_br_active() then
    -- BR registrations are live; safe to overlay content into named buffs
end
```

Eliminates the cross-mod sync rule that wt/ct/et previously had to maintain. Each consumer mod can now ship independently — install just `bt` + the consumer mod you want, and BR features for that mod work standalone.
