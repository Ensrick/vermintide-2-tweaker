# Character Weapon Variants Code Review (2026-05-01)

Reviewer pass over `character_weapon_variants/` (every file except `bundleV2/`).
Reviewed against MOD_VERSION `0.1.56-dev`. ~16 inline `--` comments added; no
functional changes. Counts: 1 confirmed bug, 1 latent bug, plus several
clarifications and small cleanup candidates.

## Summary

Health: **green-with-caveats**. The mod is structurally clean: forward-reference
hygiene is clean, hooks all use lazy string-form resolution where required,
registration is correctly deferred to `StateInGameRunning.on_enter`, deep
cloning of weapon/damage templates is correct, and the public API
(`mod.weapon_analogues`, `mod.get_analogues`) is small and stable. The main
issue is one missed `backend_id` resolution in `LootItemUnitPreviewer.spawn_units`
that exactly matches the recurring "cwv_ items resolve via backend_id, not
item_data.key" pattern. There is also a latent double-application risk for
positional offsets in the inventory previewer (no current variant uses offsets,
so it doesn't fire today).

## Confirmed bugs / potential bugs

1. **`LootItemUnitPreviewer.spawn_units` hook — missing backend_id resolution**
   (`character_weapon_variants.lua:1051`).
   `weapon_key = item_data.key or item.key` returns the BASE weapon key for
   cwv items (e.g. `es_bastard_sword`), NEVER `cwv_es_longsword`. Both
   `_skin_transform_map[weapon_key]` and `_transform_map[weapon_key]` therefore
   miss silently. Memory note `feedback_cwv_backend_id_lookup.md` predicts and
   documents this exact failure mode. The other two render paths
   (`GearUtils.create_equipment` via `_resolve_cwv_def`, `HeroPreviewer._spawn_item`
   via `_resolve_preview_def`) already do the right thing. Today this doesn't
   visibly break anything because no variant uses a non-identity scale (see
   "Doc/code mismatches" below), but the moment a real scale is reintroduced,
   the loot/illusion browser preview won't pick it up.

   Fix sketch:
   ```lua
   local def = _skin_transform_map[weapon_key] or _transform_map[weapon_key]
   if not def then
       local bid = item.backend_id
       if bid then
           local cwv_key = bid:match("^(cwv_.-)_001$")
           if cwv_key then def = _transform_map[cwv_key] end
       end
   end
   ```

2. **Offset double-application in inventory previewer (latent)**
   (`character_weapon_variants.lua:930-937`, `1039-1056`).
   Both `mod:hook("HeroPreviewer", "_spawn_item", ...)` and
   `mod:hook("MenuWorldPreviewer", "_spawn_item", ...)` are registered. Because
   `MenuWorldPreviewer._spawn_item` calls
   `MenuWorldPreviewer.super._spawn_item(self, ...)` (= HeroPreviewer's), VMF
   fires the HeroPreviewer hook from inside the super-call, then the
   MenuWorldPreviewer hook fires after. Result: `_cwv_spawn_item_post` runs
   twice per spawn for any `MenuWorldPreviewer` instance.
   - `_apply_scale` is idempotent (`Unit.set_local_scale` is absolute) — safe.
   - `_apply_offset` is **additive** (reads current position, adds offset) — a
     non-zero offset would be applied twice, doubling the displacement.
   No variant currently defines `right_hand_offset`/`left_hand_offset`, so the
   bug is dormant. Fix options: drop one of the two hooks, make `_apply_offset`
   idempotent (track baseline per unit), or guard with a per-spawn flag.

## Open questions

1. **`required_dlc = nil` and asset availability** — clearing required_dlc lets
   non-DLC users equip the variant, but the variant's right/left unit paths
   may live only in a DLC package. Empire greatsword units
   (`wpn_empire_2h_sword_*`) and `wpn_greatsword/*` are in
   `inventory_package_list.lua` (core), so `cwv_es_longsword*` is safe. The
   sword+shield variants reference `wpn_we_sword_03_t1`, `wpn_we_shield_02`,
   `wpn_axe_hatchet_t2`, `wpn_es_deus_shield_02` — all need verification on
   non-DLC users. Current variants likely work because their base weapons
   (`es_sword_shield`, `dr_shield_axe`) are not DLC-gated. But future variants
   that pull from a DLC package (e.g. `wpn_emp_gk_*` from "lake") would break
   silently for non-DLC users — the model would fail to load.

2. **`_register_custom_illusions` writes `ItemMasterList[skin_key]` directly**
   (line 573). All other item-key writes go through MIL. Skins (item_type =
   `weapon_skin`) appear to work this way historically, but if MIL's internal
   tracking matters (e.g. for cleanup on mod reload), bypassing it could be a
   problem. Probably fine, but worth a one-line comment in code explaining
   why this path is different.

3. **Multiplayer behavior with mismatched cwv items**
   (`CROSS_MOD_ARCHITECTURE.md` already calls this out): `cwv_*` backend ids
   ARE network-replicated (item_names injected into NetworkLookup), so a
   non-CWV peer would crash on receiving a cwv backend_id. Confirm before any
   public release.

## Refactor / cleanup candidates

- The two NetworkLookup-injection sites use slightly different patterns. Line
  467-471 uses an explicit `idx` variable + rawset; line 603-607 uses
  `tbl[#tbl+1] = ...` then re-reads `#tbl` for the reverse index. Both work,
  but consistency helps future readers — pick the rawset form (CHANGELOG v0.1.12
  documents the error-throwing __index reason for using rawset).
- `_resolve_cwv_def` has a fallback `local key = item_data.key or item_data.name`
  that is dead for cwv items (since key/name return the base key). Kept "just
  in case" — could be deleted if `_transform_map` keys are guaranteed to be
  cwv-prefixed (which they are, by construction from `_variant_definitions`).
- `_display_names` loop overwrites `_display_names[def.item_type]` for every
  variant sharing an item_type. All three Imperial Longsword entries produce
  the same string so it's harmless today, but the loop could break if two
  variants with the same item_type want different localized type names.
- `_create_imperial_longsword_template` and `_create_elven_sword_shield_template`
  share ~80% of their structure (clone template, walk actions, mutate sub-
  actions). A small `_create_cwv_template(base_name, new_name, mutators)` helper
  would dedupe. Not urgent.
- `_apply_offset` writes a `mod:info` log line on every offset application —
  this could spam logs if offsets are added later. Consider gating behind a
  debug setting or reducing to `mod:debug`.

## Doc/code mismatches

- **CHANGELOG v0.1.25 vs current code**: changelog states base longsword has
  `right_hand_scale = {1.0, 1.0, 1.15}` and veteran has `{0.65, 1.0, 0.85}`.
  Current code has all three Imperial Longsword variants at `{1.0, 1.0, 1.0}`
  (identity / no-op). Either revert the change (if the scaling broke
  something) or drop the field entirely so `_transform_map` doesn't pick up
  empty-effect entries. Either way, CHANGELOG should be amended in a future
  bump to reflect what shipped.
- **DEVELOPMENT.md > Registration Timing** says "hook `StateInGameRunning.on_enter`
  using `hook_safe`" — code does this correctly. ✓
- **DEVELOPMENT.md > Skin System** says "do NOT clear `skin_combination_table`"
  — code keeps it for non-longsword variants and re-points it for longsword
  variants (line 677-678). ✓
- **DEVELOPMENT.md > Adding a New Variant Weapon** doesn't mention `template`,
  `item_type`, `right_hand_scale`, `left_hand_scale`, `skin_only`, or
  `power_level` fields — these are all real, used fields. Worth a doc update.

## Settings coherence

`_data.lua` defines no widgets — only `name`, `description`, `is_togglable`.
`_localization.lua` provides only `mod_description`. There are no `mod:get(...)`
calls in `character_weapon_variants.lua`. Trivially coherent.

## Hook patterns

All hooks follow CLAUDE.md / DEVELOPMENT.md guidance:

| Hook | Form | Notes |
|------|------|-------|
| `_G.Localize` | `mod:hook(_G, ...)` | Correct — global function. |
| `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins` | `hook_safe` string-form | Lazy resolution, fires after original. |
| `StateInGameRunning.on_enter` | `hook_safe` string-form | Defers backend-dependent work. |
| `GearUtils.create_equipment` | `mod:hook` string-form | Wraps to apply transforms to result units. |
| `HeroPreviewer._spawn_item` | `mod:hook` string-form | See "double application" note below. |
| `MenuWorldPreviewer._spawn_item` | `mod:hook` string-form | Subclass hook — see POTENTIAL BUG #2. |
| `LootItemUnitPreviewer.spawn_units` | `hook_safe` string-form | See POTENTIAL BUG #1. |

No `BackendUtils.can_wield_item` hook (correctly avoided per CLAUDE.md). No
direct `set_loadout_item` hooks.

## Template cloning correctness

- `table.clone(t, true)` is a true deep clone (recursive walk) per
  `foundation/scripts/util/table.lua:31-46`. Sub-tables are freshly allocated;
  mutating the clone never reaches back to the source. Verified for
  `bastard_sword_template` and `one_handed_sword_shield_template_1`.
- Two-level iteration (`actions` -> action group -> sub-action) is the right
  depth for `anim_time_scale` / `damage_profile` mutation; those keys never
  appear deeper (e.g. inside `allowed_chain_actions` or `buff_data`).
- Damage-profile clone names use distinct prefixes per template:
  - `cwv_il_*` for imperial longsword
  - `cwv_ess_*` for elven sword+shield
  No collision. The function is idempotent (early-return on existing clone),
  so a profile shared across multiple sub-actions is cloned once.
- Critical caveat (now commented inline): if a future template re-uses a prefix
  with different multipliers, the second caller will inherit the first's
  PowerLevelTemplates entries silently. Prefix-per-mutator-set is therefore
  load-bearing — keep one prefix per `_create_*_template` function.
- `NetworkLookup.damage_profiles` injection (line 241-246) uses rawset with
  explicit idx — matches CHANGELOG v0.1.12 guidance.

## Three rendering paths audit (for model scale)

| Path | Hook | Resolution method | Status |
|------|------|------------------|--------|
| In-game | `GearUtils.create_equipment` | `_resolve_cwv_def(item_data, result.skin)` — uses `item_data.backend_id` pattern, falls back to skin map. | ✓ correct |
| Inventory preview | `HeroPreviewer._spawn_item` + `MenuWorldPreviewer._spawn_item` | `_resolve_preview_def(self, item_name)` — iterates `_item_info_by_slot` to find the entry whose `info.backend_id` matches the cwv pattern. | ✓ correct (but see double-application note for MenuWorldPreviewer instances) |
| Illusion browser | `LootItemUnitPreviewer.spawn_units` | Looks up via `item_data.key` only. | **MISSING backend_id resolution — POTENTIAL BUG #1.** |

## Item identification (backend_id pattern, base-vs-cwv template)

- Per memory note `feedback_cwv_backend_id_lookup.md`: cwv items expose
  `item_data.key = <base_weapon_key>`, `item_data.name = <base_weapon_key>`,
  `item_data.backend_id = "cwv_<...>_001"`. The cwv key is recoverable ONLY
  from backend_id.
- Per memory note `feedback_cwv_previewer_template_lookup.md`: the inventory
  previewer's `ItemHelper.get_template_by_item_name(item_name)` looks up
  `ItemMasterList[item_name].template`, where `item_name = info.name` = base
  key. So the previewer reads `Weapons.one_handed_sword_shield_template_1`,
  not `Weapons.elven_sword_shield_template`. The fix (patch the BASE template's
  `wield_anim_career_3p` for elf careers) is correctly applied at lines 349-355.
  In-game equip uses `simple_inventory_extension`'s direct read of
  `item_data.template` and so picks up `elven_sword_shield_template` directly —
  attack-event remaps reach the gameplay path even though the previewer doesn't
  see them.

## MoreItemsLibrary integration timing

- MIL is detected via `get_mod("MoreItemsLibrary")` and registration is
  deferred to `StateInGameRunning.on_enter` (string-form, lazy). The backend
  is guaranteed ready at that point.
- `_auto_registered` flag prevents re-registration on subsequent state entries.
- Backend ID is stable (`<item_key>_001`) so duplicates can't be created across
  sessions. CHANGELOG v0.1.14 confirms intent.
- After MIL registration, the code mirrors entries into `ItemMasterList`
  directly (lines 849-861). Reasoning is documented in the existing comment at
  line 752-755: HeroPreviewer.equip_item resolves via `ItemMasterList[item_name]`,
  which would crash if MIL only kept the entries in its private backend store.
- `NetworkLookup.item_names` is also populated manually post-MIL (lines 864-872)
  per CHANGELOG v0.1.24.
- Rarity is set to `"default"` during registration, then overwritten on the
  live backend item after `_refresh()` — matches the GiveWeapon pattern
  documented in CHANGELOG v0.1.18.

## Public API for cosmetics_tweaker

- `mod.weapon_analogues` — table, two entries
  (`es_2h_sword <-> wh_2h_sword`). Type is `{ [string] = { string, ... } }`.
  Stable.
- `mod.get_analogues(item_key)` — returns `mod.weapon_analogues[key]` or `{}`.
  Idempotent. Note: callers must NOT mutate the returned array because the
  fast path returns the live entry. Worth documenting in the inline comment
  added during this review.
- Both are set at file scope (line 15 / 20), well before any consumer's
  `get_mod("character_weapon_variants")` lookup could succeed — no race.
- No version field is exposed on the module table (`MOD_VERSION` is local).
  If cosmetics_tweaker ever needs version-gating ("only consume the API if
  CWV >= 0.1.45"), add `mod.api_version = 1` (or similar) so consumers can
  check capability.

## required_dlc clearing

- Rationale: `es_bastard_sword` requires `"lake"` DLC; cloning its IML entry
  inherits this field. Without clearing, MIL/backend would refuse to register
  the variant for non-DLC users. Clearing `required_dlc` removes that gate.
- Asset-load risk: the unit paths used by current variants (`wpn_empire_2h_sword_*`,
  `wpn_greatsword/*`, `wpn_we_sword_*`, `wpn_we_shield_02`, `wpn_axe_hatchet_t2`,
  `wpn_es_deus_shield_02`) are spread across multiple package list files. If
  any of these are gated to a DLC package the user doesn't own, the unit will
  fail to spawn. The Empire greatsword units used by Imperial Longsword are
  in core `inventory_package_list.lua` (verified) — safe. The other variants
  should be re-verified per-unit before broad release.
- Consider adding a `clear_required_dlc = true` opt-in field on each variant
  rather than blanket-clearing on every clone, so the fields can be re-applied
  per variant when the asset really is DLC-gated.

## Non-obvious things now clarified

- `entry.cwv_variant = true` (line 650) is a marker for sibling mods to skip
  weapon-name-keyed overrides. The existing comment at lines 647-649 is the
  authoritative explanation; nothing to add.
- `entry.name`/`.key` are deliberately NOT overridden — downstream lookups fall
  back to `ItemMasterList[item.name]` and would crash if name were nil or
  pointed to a non-existent key. Confirmed by tracing
  `HeroPreviewer.equip_item` and `LootItemUnitPreviewer._load_item_units`.
- `skin_only = true` (used by `cwv_es_longsword_helmgart`) is checked in
  `_auto_register_all` (line 830) but NOT in `_register_variant_skins` — the
  skin still gets registered, only the inventory-item registration is skipped.
  This is the correct behavior for an "illusion-only" variant.

## Dead code

- `_apply_weapon_unlocks` only contains one entry (`wh_1h_axe` for Kruber
  careers). The `_weapon_unlocks` infrastructure is generic enough to host
  more — fine as-is.
- The `key` fallback in `_resolve_cwv_def` (line 952-954) is unreachable for
  current cwv items (key/name return the base key). Kept for future
  flexibility.
- Identity scales `{1.0, 1.0, 1.0}` on the three Imperial Longsword variants
  effectively disable the scale path while still putting them in
  `_transform_map`. Either restore the v0.1.25 values or drop the fields.

## Notes for future AI agents

1. **Always resolve cwv items via `backend_id`**, not `item_data.key` — see
   `feedback_cwv_backend_id_lookup.md`. The `LootItemUnitPreviewer` hook is
   currently the only render path missing this; if you add another render-path
   hook, do the backend_id match first.
2. **Patch the BASE template, not just the cloned template** when adding a
   `wield_anim_career_3p` or any other field the inventory previewer reads —
   see `feedback_cwv_previewer_template_lookup.md`. The cloned template is
   only consulted for in-game gameplay (`simple_inventory_extension` reads
   `item_data.template` directly).
3. **Damage-profile prefix discipline** — one prefix per multiplier set. If
   you write a third `_create_*_template` function, give it a brand-new
   prefix; reusing `cwv_il_` or `cwv_ess_` will silently inherit those
   templates' multipliers (the function early-returns on existing clones).
4. **MIL doesn't inject into `NetworkLookup.item_names`** — you must do it
   manually after `add_mod_items_to_local_backend` (see CHANGELOG v0.1.24).
   Same applies for `NetworkLookup.weapon_skins` (use rawget/rawset because
   of the error-throwing __index — see CHANGELOG v0.1.12).
5. **Don't override `entry.name` or `entry.key`** when cloning — downstream
   lookups crash on nil. Custom display names live in the Localize hook
   (`<item_key>_name` -> display string).
6. **MenuWorldPreviewer extends HeroPreviewer** — be careful when hooking
   `_spawn_item` on both; the subclass calls `super._spawn_item`, so the
   parent hook fires for subclass instances. Pick one or guard for double
   firing.
7. **Hot-reload is not safe** — restart the game after every CWV deploy.
   This mod hooks `GearUtils.create_equipment` (same engine path as
   weapon_tweaker / cosmetics_tweaker, with the same C++ resource lock issue).
