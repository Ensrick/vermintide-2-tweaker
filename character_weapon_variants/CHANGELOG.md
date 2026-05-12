# Character Weapon Variants — Changelog

## 0.1.324-dev (2026-05-12) — Tuskgor Javelin: runtime-hide the duplicate 3P spare boar spear
- After v0.1.321 restored `ammo_unit = boar spear` (mandatory for projectile/pickup paths — see `feedback_cwv_ammo_unit_required.md`), the held mesh renders correctly again, but 3P shows TWO boar spears (held + spare offhand). Per the v0.1.321 TODO entry: fix by runtime-hiding the spawned `left_ammo_unit_3p` instance, not by zeroing the data field.
- Implementation: extended two existing hooks (no new hook registrations to avoid VMF hook_safe chaining issues per `feedback_vmf_hook_safe_no_chain.md`):
  1. `SimpleInventoryExtension._wield_slot` POST — catches the explicit `Unit.set_unit_visibility(slot_data.left_ammo_unit_3p, true)` at vanilla `simple_inventory_extension.lua:2153`. After vanilla wields the slot, if backend_id matches `^cwv_e[sw]_javelin_`, set `slot_data.left_ammo_unit_3p` (and `right_ammo_unit_3p` defensively) visibility false.
  2. `SimpleInventoryExtension.show_third_person_inventory` POST — catches the FP→3P camera-toggle path that re-shows 3P inventory. Same gate, same hide. show=false naturally hides everything, no work needed.
- 1P offhand spare left visible — user only complained about 3P.
- Other equip side effects (projectile spawn at throw time, link_pickup respawn, ammo decrement visuals) are untouched because we hide a SPAWNED UNIT INSTANCE, not the underlying data field. Projectile system and pickup system both look up `slot_data.left_hand_unit_name` / `ammo_unit` strings, not the spawned unit refs — so they keep working.

## 0.1.323-dev (2026-05-12) — Old Musket: ship CC-BY 4.0 attribution
- Source model "Old Musket" by [Lathander](https://sketchfab.com/Lathander) (Sketchfab) was added in v0.1.272+ without an attribution block. Sketchfab's "Free" download category includes CC-BY 4.0 licensed models, which require credit, a link to the source, a link to the license, and indication of changes made. The mod was shipping without any of these.
- Added `THIRD_PARTY_NOTICES.md` at the mod root with the full attribution: title, author, source URL, license URL, list of technical conversions applied (DAE→FBX, material rename, PNG retexture). The notices file is the canonical credit; the Workshop description carries an abbreviated version so subscribers see it.
- Updated `itemV2.cfg` description with a `[h1]Credits[/h1]` section linking author, license, and source.
- No code changes; no behaviour changes. **DoD:** N/A (asset-license correction, not a new variant).

## 0.1.322-dev (2026-05-12) — cwv_es_longsword_shield: match Imperial Longsword stat tune on sword swings only
- User: "I never changed the stats for this weapon did I? Can we make all the non-shield attacks have the same changes as the Imperial Longsword does?" — confirmed `cwv_es_longsword_shield` had no `template` field on the def, so it was running the base `one_handed_sword_shield_template_2` untouched.
- Added `_create_imperial_longsword_shield_template`: clones the base, walks `template.actions` two levels deep, and applies the same multipliers as `imperial_longsword_template` (-15% damage, +15% speed, +15% cleave, -15% stagger) to every sub-action that isn't a shield action.
- Skip filter: `kind == "block"` OR `damage_profile` starts with `"shield_"`. Catches the block action and every `shield_slam*` / `shield_push` damage profile. The push baseline (`damage_profile_inner` / `damage_profile_outer` dual-profile sub-action) is naturally skipped since the filter only inspects plain `damage_profile`.
- Reuses the `cwv_il_` prefix from the 2H template — identical multipliers, no profile-name overlap (bastard sword uses 2H slashing profiles; bret sword+shield uses 1h slashing profiles), and `_clone_damage_profile` is idempotent.
- Wired via `template = "imperial_longsword_shield_template"` on the variant def.

## 0.1.321-dev (2026-05-12) — Tuskgor Javelin: revert v0.1.259 (broke held mesh) + revert v0.1.258/263 stick depth
- User: "the javelin is invisible". Root cause confirmed: my v0.1.259 fix setting `ammo_unit = "units/weapons/player/wpn_invisible_weapon"` on both `cwv_es_javelin` and `cwv_wh_javelin` defs (to suppress the 3P offhand spare boar spear) broke the held-mesh rendering. `feedback_cwv_ammo_unit_required.md` explicitly says ammo_unit must mirror the base for ammo weapons — downstream paths (previewer, projectile spawn, pickup respawn) read it for held visuals and throw it as a fallback when the held unit isn't present. Pointing it at the invisible-weapon unit blanked those code paths.
- Fix: removed `ammo_unit = ...invisible_weapon` from both def entries. The skin-registration fallback at line ~5816 (`ammo_unit = def.ammo_unit or (base.ammo_unit and def.left_hand_unit)`) now resolves to `def.left_hand_unit` = boar spear, same as before v0.1.259.
- Side effect returning: 3P will show a duplicate boar spear as the offhand spare (the "two boar spears" symptom v0.1.259 was chasing). Captured as a TODO entry under "Tuskgor Javelin polish" — correct fix is to keep ammo_unit pointing at the boar spear and runtime-hide the spawned 3P ammo unit instance via `Unit.set_unit_visibility(false)` in a `GearUtils.spawn_inventory_unit` POST hook, not blanket the data field.
- Also reverted v0.1.258/0.1.263 pull-back-from-wall fix (`_TJ_VISUAL_PULL_BACK_M = 0.60 → 0`). User reports the math didn't visibly move the stuck-javelin visual out of the wall — `pos - Quaternion.forward(rot) * offset` is either reading the wrong rotation axis or the link_pickup system snaps the visual back to the parent post-spawn. Constant kept (set to 0, no-op) so the offset-math branch is in place to be re-tuned once the right axis/coordinate frame is identified; full debug plan captured as TODO.

## 0.1.320-dev (2026-05-12) — Axe and Shield: curated illusion picker
- User: "make the axe+shield weapon have illusions too like other CWV weapons".
- Both cwv_es_axe_shield (blacksmith default) and cwv_es_axe_shield_veteran (unique) now share `item_type = "cwv_es_axe_shield"`, mirroring how cwv_imperial_longsword's default + blackguard variants share a single item_type and skin pool.
- New `cwv_es_axe_shield_skins` skin_combination_table wired into `_seed_targets` and `_item_type_to_skin_table`. Both variants auto-seed into their respective rarity tiers; the blacksmith default's appearance stays locked by the BackendUtils.get_item_template hook (illusions visually no-op on it, same as every other CWV blacksmith default).
- `_register_axe_shield_illusions()` mirrors `_register_imperial_longsword_shield_illusions()`: 12 hardcoded (Empire shield mesh × Empire hatchet mesh) pairs across plentiful → magic rarity tiers. Hatchet meshes drawn from the `wh_1h_axe` skin pool (wpn_axe_02 / wpn_axe_03 / wpn_axe_hatchet tiers — Saltzpyre's Empire-style hatchets, same family the default + veteran variants already use). Shields are the same wpn_empire_shield_01..05 + runed/magic set the longsword+shield picker uses.
- Mesh-path locals wrapped in `do ... end` per the Lua 5.1 200-local main-chunk rule.
- Variant's `display_unit` set to `display_shield` (generic) — matches vanilla dwarven dr_shield_axe skins; there is no `display_shield_axe`.
- **DoD:** Universal (item_type wired, skin combos seeded, forward-ref audit clean) + G-CUSTOM-ILLUSION (curated pool, matching_item_key → variant key, can_wield gated to ES careers, NetworkLookup updated). Live verification (in-game preview of the picker + applied skin on veteran instance) deferred to user's next session.

## 0.1.319-dev (2026-05-12) — Old Musket: 3P-RANGED rotation baked
- User live-tune via `rotmul`: X(-90°) then Z(+90°). Baked the composed quaternion as the new 3P-RANGED default.
- Position and scale remain identity for 3P-RANGED — user will tune offsets in a subsequent session.

## 0.1.318-dev (2026-05-12) — Old Musket: 3P transform split by stance, MELEE defaults locked in
- User: "rotation for 3rd person melee should be 0 1 0 -90, pos 0 0.045, 0.1"
- Split 3P transform state into `_3P_RANGED` and `_3P_MELEE` buckets (mirrors what 1P already had).
- 3P-MELEE defaults baked: pos `(0, 0.045, 0.1)`, rot axis `(0, 1, 0) @ -90°`, scale identity. 3P-RANGED defaults stay identity (user-confirmed at v0.1.295).
- New weak-keyed tracking sets `_CWV_OLD_MUSKET_UNITS_3P_RANGED` / `_3P_MELEE`. `_track_old_musket_unit` and `_apply_old_musket_transform` route by `(perspective, mode)` for the 3P side too.
- Stance toggle in-mission (spawn_inventory_unit hook) already passes `_mode` derived from `item_template`; the 3P unit now picks up the per-stance transform.
- Inventory previewer (`_cwv_spawn_item_post`) reads `item_data.mod_data.cwv_musket_stance` to determine the displayed mode (default ranged) and applies the matching 3P transform.
- 10 new/replaced commands replace the single `cwv_om_*_3p` set:
  - `cwv_om_pos_3p_r / _3p_m <x> <y> <z>`
  - `cwv_om_rot_3p_r / _3p_m <ax> <ay> <az> <deg>`
  - `cwv_om_rotmul_3p_r / _3p_m <ax> <ay> <az> <deg>`
  - `cwv_om_eul_3p_r / _3p_m <x_deg> <y_deg> <z_deg>`
  - `cwv_om_scale_3p_r / _3p_m <x> <y> <z>`
  - `cwv_om_show` echoes all four buckets (1P-R / 1P-M / 3P-R / 3P-M).

## 0.1.317-dev (2026-05-12) — Old Musket: fix missing textures in keep inventory 3P preview
- User: rifle is in the inventory 3P model with no texture. (3P transforms not yet tuned, separate concern.)
- Researched memory + CLAUDE.md hook-derived-class rule. Confirmed our existing `_cwv_spawn_item_post` IS hooked on both `HeroPreviewer._spawn_item` AND `MenuWorldPreviewer._spawn_item`. Per the new `feedback_inventory_preview_hook_menuworldpreviewer.md` rule, only the MenuWorldPreviewer hook fires for the keep inventory previewer — the HeroPreviewer wrapper is bypassed because MenuWorldPreviewer copies parent methods at class-def time. So the right hook IS registered.
- **Actual root cause**: `_resolve_preview_def`'s backend_id regex was `"^(cwv_.-)_001$"` — captured ONLY instance suffix `_001`. cwv_es_musket_old ships with `instances = 2` (per the variant def), so instance `_002` failed the regex, returned nil, and `_cwv_spawn_item_post` exited early before reaching the texture binding. Result: the FIRST musket the previewer rendered (e.g. instance _001) had textures; the SECOND (instance _002) was white. Likely also why "I feel I mentioned this quite often" — every variant with `instances > 1` has been affected since v0.1.271 added the multi-instance feature.
- Fix: regex relaxed to `"^(cwv_.-)_%d%d%d$"` — matches any 3-digit instance suffix.

## 0.1.316-dev (2026-05-12) — Cross-slot: scope back via consolidated post-filter
- User confirmed v0.1.313's broad behavior works ("all ranged weapons are enabled for melee slots"). Career mutation is reaching CareerSettings successfully now that it's deferred to `on_all_mods_loaded`.
- Replaced the v0.1.302/306 dual-hook setup (inject + post-filter) with a **single consolidated post-filter** on `BackendInterfaceItemPlayfab.get_filtered_items`. Avoids any chain-order interaction between two hooks on the same method.
- Hook only runs for the melee-slot filter (`slot_type == melee` substring match). For each item: native melee items (`slot_type ~= "ranged"`) kept as-is; ranged items only kept if `_is_cwv_musket_item` returns true (which iterates `_CWV_CROSS_SLOT_PREFIXES = { "cwv_es_musket", "cwv_es_javelin_shield" }`). Logs kept/dropped counts for diagnostics.
- Ranged-slot filter untouched — vanilla ranged items continue to appear there naturally.

## 0.1.315-dev (2026-05-11) — Sigmarite Greathammer cosmetics: Kruber + Warrior Priest skins

User: "The 'Sigmarite Greathammer' has no illusions/cosmetics, add all Kruber's normal greathammer cosmetics to it in addition to Saltzpyre's Warrior Priest cosmetic options too. All those."

**Root cause:** `cwv_es_priest_greathammer` had no `item_type` set, so it inherited `skin_combination_table = "wh_2h_hammer_skins"` from its `wh_2h_hammer` clone. The vanilla Warrior Priest combo table was either filtered out by cosmetics_tweaker (mesh mismatch) or simply did not flow into the variant's picker — net result: empty illusion list.

**Fix:** Mirror the `cwv_es_warpriest_hammer` recipe — give the variant its own item_type and dedicated combo table, then seed both Kruber and Warrior Priest greathammer meshes as illusion entries.

- Added `item_type = "cwv_es_priest_greathammer"` to the variant def.
- Registered `cwv_es_priest_greathammer → "cwv_es_priest_greathammer_skins"` in `_seed_targets` and `_item_type_to_skin_table`.
- Appended 18 entries to `_custom_illusions` (9 Kruber `es_2h_hammer_skin_*` + 9 Saltzpyre `wh_2h_hammer_skin_*`) with `target_combo = "cwv_es_priest_greathammer_skins"`, `matching_weapon = "wh_2h_hammer"` (so `_apply_skin_to_item` finds `two_handed_hammer_priest_template`), `can_wield = _es_careers`. No scale/offset — both source families are 2H greathammers of comparable size, no rescale needed.

Source skins that aren't defined in `WeaponSkins.skins` at load time (e.g. DLCs the user doesn't own) will warn and skip via `_register_custom_illusions`'s existing guard — no crash.

**DoD:** trait-gated gates not affected; this is purely a cosmetic-pool expansion on an existing variant. Manual verify: enter blacksmith on any Kruber career, view the Sigmarite Greathammer, open the illusion picker, see ~18 entries (or fewer if DLCs missing). Equipping each should swap visuals without breaking the priest moveset.

## 0.1.314-dev (2026-05-11) — Outrider Grenade Launcher reload slowed

Bumped `_OUTRIDER_RELOAD_MULT` from `0.65` → `0.75`. Per-user request to slow the grenade launcher's reload relative to the previous tuning while keeping it faster than the vanilla trollhammer base.

**DoD:** trait-gated gates not affected (single-key constant tweak). Manual verify: load Kruber outrider, fire to empty, observe new reload duration is ~25% faster than trollhammer (was ~35% faster).

## 0.1.313-dev (2026-05-11) — Cross-slot: BACK to broad v0.1.304 behavior + diagnostics, REMOVE post-filter
- User: "Not available in the melee slot." Both v0.1.311 (custom slot_type) and v0.1.312 (post-filter) failed. Strip everything back to the v0.1.304 approach that we know surfaced items, plus diagnostic logging to confirm the career mutation actually runs.
- Career-mutation block now iterates ALL of `CareerSettings` (not just a hardcoded Kruber career list) — picks up any career whose `item_slot_types_by_slot_name.slot_melee` is `{"melee"}` and appends `"ranged"`. Also cleans up any `cwv_dual` leftovers from v0.1.311. Uses `mod:echo` to surface the result in the in-game console so the user sees how many careers got extended.
- **Deferred the mutation via `mod.on_all_mods_loaded`** to guarantee `CareerSettings` is fully populated by then (v0.1.304-312 ran at mod-init time which may be too early).
- **Post-filter removed.** Until cross-slot is confirmed working at all, every ranged weapon shows in Kruber's melee grid (same as v0.1.304). Once confirmed, will re-add a scoped filter that doesn't break the path.

## 0.1.312-dev (2026-05-11) — Cross-slot: broad career override + scoped post-filter
- User: "Not available at all, as if it doesn't exist for ranged or melee." v0.1.311's `entry.slot_type = "cwv_dual"` made the items vanish from both grids — MIL or vanilla silently drops items with unrecognized slot_type values.
- Final architecture: combine the v0.1.304 broad career override (which actually surfaced items in the melee grid — confirmed working) with a post-filter on `get_filtered_items` that removes non-allowlisted ranged items from the melee result. Net effect: only items flagged `def.cross_slot = true` (currently just `cwv_es_musket_old`) appear in both melee and ranged grids; other ranged weapons stay in slot_ranged only.
- Reverted: `entry.slot_type = "cwv_dual"` (back to inherited "ranged"), the `_get_slot_by_type` alias hook (no longer needed since item keeps a known slot_type), and the v0.1.311 career-extension that added "cwv_dual" to slot lists.
- Added: `_extend_kruber_melee_slot_with_ranged` cleans up stale "cwv_dual" entries from v0.1.311 attempts AND appends "ranged" to slot_melee (idempotent). Plus a post-filter on `get_filtered_items` for the `slot_type == melee` filter case: keeps native melee items as-is; for ranged items, keeps only those matching `_is_cwv_musket_item` (which itself iterates `_CWV_CROSS_SLOT_PREFIXES`).
- The post-filter does NOT touch the ranged-slot filter — vanilla ranged items appear there naturally, no scoping needed.
- Restart required for the broad career mutation to apply cleanly (the v0.1.311 "cwv_dual" entries that may still be in CareerSettings get cleaned up on next init).

## 0.1.311-dev (2026-05-11) — Cross-slot: custom slot_type "cwv_dual" (scoped + reliable)
- User: "It's now no longer available for melee slot." After v0.1.310 reverted the broad career override and relied purely on the cross-slot inject hook, the musket no longer surfaces in the melee grid. The inject hook is logically correct but evidently doesn't work in the user's live setup; v0.1.268 history shows it once did, so something downstream may have changed.
- Switched to a **custom slot_type** approach. Best of both: scoped (only cwv variants we flag get it) AND career-filter-level (so the items DO show in the grid).
  - Variants with `def.cross_slot = true` get `entry.slot_type = "cwv_dual"` (set in `_build_entry`). Currently only `cwv_es_musket_old`.
  - Kruber's 4 careers (es_mercenary / es_huntsman / es_knight / es_questingknight) have `item_slot_types_by_slot_name.slot_melee` AND `slot_ranged` extended with `"cwv_dual"`. So the melee-slot filter becomes `slot_type == melee or slot_type == cwv_dual`, ranged becomes `slot_type == ranged or slot_type == cwv_dual`. Our flagged items match both; vanilla rifles (`slot_type = "ranged"`) match only ranged.
  - Block also CLEANS UP any leftover `"ranged"` entry on slot_melee from v0.1.304's mutation (in case the user hasn't restarted yet to revert it).
  - Hooked `HeroViewStateOverview._get_slot_by_type` to alias `"cwv_dual" → "ranged"` so any no-strict-slot equip path (e.g. cosmetic-loadout sets, loadout reset) resolves to the ranged slot.

## 0.1.310-dev (2026-05-11) — Scope cross-slot to only musket + (future) jav+shield families
- User: "Other ranged weapons are showing up for use in melee, it's only the musket and the jav+shield that should be right now."
- **Reverted v0.1.304's career override.** That block extended Kruber's `slot_melee` to accept `"ranged"`, making EVERY ranged weapon (vanilla rifle / blunderbuss / repeater / cwv_es_outrider_grenade_launcher / etc.) appear in the melee inventory grid for all 4 empire careers. Too broad. The `_extend_kruber_melee_slot` block is now an empty placeholder — runtime CareerSettings mutation from v0.1.304 persists for the current session, so a game restart is needed to fully revert.
- **Switched to a scoped allowlist for cross-slot inject.** New constant `_CWV_CROSS_SLOT_PREFIXES = { "cwv_es_musket", "cwv_es_javelin_shield" }`. `_is_cwv_musket_item` now iterates the allowlist instead of the single hardcoded `"cwv_es_musket"` match. `string.find(key, prefix, 1, true) == 1` is a plain prefix match (covers per-instance backend_ids like `cwv_es_musket_old_001`).
- The `"cwv_es_javelin_shield"` prefix is kept forward-compat — v0.1.308 reverted that variant but TODO says it'll be re-implemented mirroring the cwv_es_musket_old recipe. When it returns, the cross-slot inject already accepts it without further changes.

## 0.1.309-dev (2026-05-11) — cwv_es_longsword_shield: relax 3P sword shrink by +0.05 per axis
- User feedback: v0.1.265's 3P shrink `{0.85, 0.65, 0.75}` was too aggressive next to the shield.
- Bumped `_type_transforms.cwv_es_longsword_shield.right_hand_scale_3p` from `{0.85, 0.65, 0.75}` → `{0.9, 0.7, 0.8}` (+0.05 every axis). 1P unchanged (`{1.0, 0.8, 0.9}`), grip offset unchanged.
- Affects right-hand sword mesh only; shield (left) still untouched.

## 0.1.308-dev (2026-05-11) — Revert v0.1.288 cwv_es_javelin_shield (broke cwv_es_javelin model rendering)
- Reverted: variant def `cwv_es_javelin_shield`, templates `cwv_javelin_shield_template_ranged` / `cwv_javelin_shield_template_melee`, toggle helper `_toggle_javelin_shield_stance_and_rewield`, `_attach_stance_toggle_action_three` helper, the `_force_load_javelin_shield_melee_assets` block, and the second `BackendUtils.get_item_template` hook block.
- User report: after v0.1.288 the existing Tuskgor Javelin (`cwv_es_javelin`) lost its boar-spear left-hand model in both 1P and 3P; 3P showed an unwanted (wrong) left-hand model and no model on the right. Stance toggle on the new variant did nothing visible. Reverting to v0.1.307 baseline to confirm cwv_es_javelin works again, then re-approach by following `cwv_es_musket_old` (the currently-working stance-toggle variant) exactly — a single consolidated `BackendUtils.get_item_template` hook plus a `slot_data.skin`-pattern-aware projectile init hook, instead of a parallel second hook block.
- TODO entry for `cwv_es_javelin_shield` remains in `character_weapon_variants/TODO.md` — to be re-implemented by mirroring the live `cwv_es_musket_old` recipe rather than the older (commented-out) `cwv_es_musket` recipe in `reference_cwv_stance_toggle_recipe.md`.

## 0.1.307-dev (2026-05-11) — Old Musket: stance-toggle was the actual free-reload exploit (not _wield_slot)
- User: "None of it works, try again." Traced the exploit precisely — the v0.1.305/306 `_wield_slot` PRE/POST mechanism was correct but **wasn't the right hook**. The real exploit is in **our own** `_toggle_musket_stance_and_rewield` helper, not vanilla wield. Three compounding issues:
  1. We captured ammo state as `total_ammo_fraction = (current + reserve) / max`. The fraction collapses chamber and reserve into one number. With 0 chambered + 10 reserve, fraction = 10/11. Mid-reload (still 0 + 10), same fraction.
  2. Passed that fraction as `ammo_percent` to `add_equipment`. Vanilla reconstructs: `_start_ammo = round(0.909 * 11) = 10`, then `_current_ammo = min(ammo_per_clip, start_ammo) = min(1, 10) = 1`. **Always 1 chambered after spawn, regardless of pre-toggle state.** Free chamber refill every stance toggle.
  3. The stance-toggle path destroys+adds+wields rather than going through `_wield_slot`'s unwield-then-wield flow, so my v0.1.306 PRE-hook never saw the outgoing-reloading state — flag was never set, POST cancellation never fired.
- Fix: capture `_current_ammo`, `_available_ammo`, `_shots_fired`, and `is_reloading()` SEPARATELY on the outgoing ammo extension. Persist all four on `item_data.mod_data` (so they survive ranged→melee→ranged where the melee unit has no ammo extension). Pass `ammo_percent = 0` to `add_equipment` (so vanilla spawns the unit at 0/0). Then POST-wield, find the new ammo extension and restore the precise captured values. If reloading was in progress at toggle time, also set `cwv_musket_reload_interrupted = true` AND directly call `abort_reload` on the freshly-spawned extension (since vanilla may have auto-started a reload during wield while ammo was momentarily 0).
- Also re-sync the shared ammo pool from the restored reserve so any other equipped cwv musket sees the same reserve number.

## 0.1.306-dev (2026-05-11) — Old Musket: shared reserve ammo pool + reload-exploit fix (real this time)
- **Reload-cancel exploit (v0.1.305 fix didn't take).** Root cause: my `_wield_slot` PRE/POST checks used `item_data.backend_id`, but cwv entries store backend_id in `item_data.mod_data.backend_id` (see `_build_entry`). The regex never matched, the flag was never set, the auto-reload-on-wield was never cancelled. Added helper `_item_backend_id(item_data)` that checks both locations (direct field AND mod_data fallback). PRE detects reloading-cwv-musket being unwielded → marks `item_data.mod_data.cwv_musket_reload_interrupted`. POST: if incoming has the flag and vanilla just kicked off auto-reload, abort it and clear the flag (one-shot, manual R works normally afterward).
- **Shared reserve ammo pool across cwv musket items.** Per user spec: when cwv musket is equipped in both slot_melee and slot_ranged, each item keeps its own CHAMBER (`_current_ammo`, capped by `ammo_per_clip = 1`) but the RESERVE (`_available_ammo`) is pooled. Max reserve per musket = 10 (max_ammo 11 - clip 1). Two equipped = 20 shared reserve + 1+1 separate chambers.
  - Mechanism: weak-keyed set `_CWV_MUSKET_AMMO_EXTS` tracks registered ammo extensions. Each cwv musket's ammo extension is marked + registered in our existing `GearUtils.spawn_inventory_unit` post-hook for cwv_es_musket_old items.
  - Sync helper `_cwv_musket_sync_pool(source_ext)` copies the source's `_available_ammo` (capped by `count × 10`) to every other alive pool member.
  - Hook `GenericAmmoUserExtension.update` POST — when vanilla's reload-completion mutates `_available_ammo` in-place (line 174 of vanilla extension), our hook detects the change and sync's pool members.
  - Hook `GenericAmmoUserExtension.add_ammo` POST — ammo pickups propagate to pool.
  - New ext registration inherits the existing pool value (so a freshly-spawned second musket sees pool ammo, not a default reset).
- New diagnostic command: **`cwv_musket_ammo_diag`** dumps every alive cwv musket ammo extension's `_current_ammo` / `_available_ammo` / `_shots_fired` / `_next_reload_time` plus the pool cap. Use to verify pool behavior at runtime.

## 0.1.305-dev (2026-05-11) — Old Musket: ammo + spread + penetration + anti-swap-exploit
- **Fix the Lua 200-locals compile error.** v0.1.304 hit the Lua 5.1 main-chunk limit. Wrapped the v0.1.300 / v0.1.301 / v0.1.304 helper blocks in `do ... end` so the locals declared inside don't consume top-level slots.
- **Tuning per user spec.** All values relative to the **vanilla** rifle, not stacked on the (on-ice) cwv_es_musket modifiers:
  - Reload time: **1.5x** vanilla (already done in v0.1.300, confirmed)
  - Max ammo: **11** (vanilla rifle ships with 16)
  - Hip-fire spread: **1.5x wider cone** via new `SpreadTemplates.cwv_old_musket`. Scaled `continuous.{still,moving,crouch_still,crouch_moving}.max_pitch/max_yaw` only — `zoomed_*` (ironsights / ADS) cones left at vanilla.
  - Penetration: **cleave_distribution.attack = 1.5** (vanilla shot_sniper = 0.3) so the shot punches through ~6 regular enemies. `impact = 0.6`. Plus `armor_modifier_near.attack[4..6]` and `armor_modifier_far.attack[4..6]` each bumped by +0.2 so the shot reads as "a bit better through armor" on the super-armored / berserker / chaos-warrior tiers, without becoming a tank-deleter.
- **Anti-exploit: reload-cancel-via-swap.** User report: empty rifle mid-reload → swap to melee → swap back → fully reloaded. Root cause: vanilla `SimpleInventoryExtension._wield_slot:2046-2068` auto-triggers a reload on wield when `ammo_count == 0`. The player could swap-cycle to "fake" a free reload (visually it appeared instantly loaded because the wield animation finished before the reload state was visible).
  - Fix: replaced the existing v0.1.281 `hook_safe` on `_wield_slot` with a full `mod:hook` wrapper. PRE-wield: detect if the outgoing weapon is a cwv musket variant currently reloading; if so, set `item_data.mod_data.cwv_musket_reload_interrupted = true`. POST-wield: if the incoming weapon is a flagged cwv musket and vanilla just kicked off the auto-reload, call `abort_reload` on it and clear the flag (one-shot — a future manual reload via R works normally).
  - The bayonet-visibility sync (v0.1.281 behavior) is preserved by running it at the end of the new wrapper.

## 0.1.304-dev (2026-05-11) — Old Musket: extend Kruber's melee slot to accept ranged weapons (canonical fix)
- Compile error after v0.1.304: `main function has more than 200 local variables`. Lua 5.1 / LuaJIT have a hard limit of 200 locals in any single function (including the top-level chunk). The mod file accumulated past it. Fixed by wrapping the v0.1.300 + v0.1.301 Old Musket template setup blocks in `do ... end` scopes — locals declared inside go out of scope at the `end`, freeing slots back to the main chunk. Same wrap applied to the new v0.1.304 `_extend_kruber_melee_slot` helper.
- User-spec stat tuning for Old Musket (all relative to **vanilla** rifle baseline, not stacked on the existing cwv_es_musket modifiers):
  - Reload time: **1.5x** vanilla (confirmed already in place from v0.1.300)
  - Max ammo: **11** (vanilla rifle has 16)
  - Hip-fire spread cone: **1.5x** wider via cloned `SpreadTemplates.cwv_old_musket`. Scaled `continuous.{still, moving, crouch_still, crouch_moving}.max_pitch / max_yaw` only — `zoomed_*` (ironsights ADS) left at vanilla so aimed-down-sights stays precise. `template.default_spread_template = "cwv_old_musket"` on `old_musket_template`.

## 0.1.304-dev (2026-05-11) — Old Musket: extend Kruber's melee slot to accept ranged weapons (canonical fix)
- v0.1.302's cross-slot inject was logically correct but evidently not surfacing the variant in the melee slot for the user. Switched to the **vanilla pattern** Fatshark themselves used for the Outcast Engineer's crank gun: modify the career's `item_slot_types_by_slot_name`. The Engineer's `career_settings_bless.lua:84` lists `slot_ranged = { "melee", "ranged" }` so the ranged slot grid accepts both. Mirroring that for Kruber's melee slot.
- New `_extend_kruber_melee_slot()` runs at mod init. Walks `CareerSettings.es_mercenary / es_huntsman / es_knight / es_questingknight` and appends `"ranged"` to each career's `item_slot_types_by_slot_name.slot_melee` (idempotent — won't duplicate). The 4 empire careers' melee inventory grid now accepts items with slot_type "melee" OR "ranged". cwv_es_musket_old (slot_type=ranged via inherited es_handgun) is now natively in the melee grid filter.
- Trade-off: ALL ranged weapons (vanilla rifle / blunderbuss / repeater / cwv_es_outrider_grenade_launcher etc.) ALSO appear in Kruber's melee grid for these 4 careers. Acceptable per user direction ("ENABLED FOR THE MELEE SLOT") and consistent with how the Engineer is set up by Fatshark. If we ever need to scope tighter, the alternative is using a custom slot_type per-variant + adding that custom type to both grids — but that breaks the no-strict-slot equip path (`_get_slot_by_type` returns nil for unknown types).
- The cross-slot inject hook from v0.1.302 stays in place as a belt-and-braces backup for any UI path that calls `get_filtered_items` with a non-career-derived filter. Not load-bearing anymore.

## 0.1.303-dev (2026-05-11) — Old Musket: diagnostic logging for melee-slot equip + cwv_musket_dump command
- User report: v0.1.302's cross-slot re-enable didn't actually surface the variant in the melee slot. Hook code looks logically correct; verified deploy bundle contains the new strings; can't reproduce without instrumentation.
- Added verbose log line on EVERY firing of the `BackendInterfaceItemPlayfab.get_filtered_items` hook for slot-type filters. Prints the exact filter string, count of items vanilla returned, count of cwv musket items considered, count injected, and the list of seen backend_ids. Should reveal whether the hook is firing, whether the items are visible in `all_items`, and whether they got appended.
- New command `cwv_musket_dump`: walks the player's backend mirror and prints every musket-keyed item with its `slot_type` / `template` / `rarity`. Also prints the `ItemMasterList` entries for `cwv_es_musket_old` / `cwv_es_musket` / `es_handgun` and confirms `Weapons.old_musket_template` / `_melee` are registered.

## 0.1.302-dev (2026-05-11) — Old Musket: enable equip in melee inventory slot (undo v0.1.300 cross-slot exclusion)
- User report (3rd attempt to make it land): "It needs to be ENABLED FOR THE MELEE SLOT." The earlier instruction in v0.1.300 ("not enabled for usage in the melee slot") was a **report of current state**, not an instruction to remove the variant from the melee grid — the user wanted it added to the melee grid since it wasn't there.
- Undid the v0.1.300 cross-slot exclusion. The `_is_cwv_musket_item` filter in `BackendInterfaceItemPlayfab.get_filtered_items` now injects cwv_es_musket_old items into both the ranged and melee inventory grids, same as cwv_es_musket would.
- Stance toggle behavior unchanged (works in either slot — vanilla just sees a single item; the slot it's equipped in is independent of the moveset template).

## 0.1.301-dev (2026-05-11) — Old Musket: restore stance toggle (ranged-slot-only, but special key still flips moveset)
- User report: "I lost the ability to switch between melee and ranged using the weapon special key." Distinguished v0.1.300 "ranged-only" instruction — the user meant **ranged inventory SLOT only**, NOT no stance toggle. The bayonet-mode behavior (special key swap to polearm moveset) should stay.
- Added: `Weapons.old_musket_template_melee` — clone of `two_handed_heavy_spears_template` (Tuskgor spear, same base as cwv_es_musket's bayonet stance) with:
  - **range_mod 1.2** on every sub-action that authors one (absolute, vs vanilla spear's 1.35)
  - **0.9x attack damage** on cloned damage profiles (keys like `cwv_old_musket_melee_heavy_slashing_smiter_stab_polearm`). Stagger left at vanilla 1.0x (user didn't ask for stagger change). Per user "based on the original rifle" — anchored to vanilla spear baseline, not the existing musket bayonet's modifiers.
  - Action_three stance toggle → `_toggle_musket_stance_and_rewield` (generalized below)
  - `display_unit` set to `display_1h_handguns` (mirrors musket_template_melee)
- Added: `action_three` stance toggle on `old_musket_template` (ranged side). Same dummy-action pattern + `_toggle_musket_stance_and_rewield` call as `musket_template`.
- Generalized: `_toggle_musket_stance_and_rewield` gate now accepts `old_musket_template / _melee` templates in addition to `musket_template / _melee`. Stance flag (`item_data.mod_data.cwv_musket_stance`) is per-item so no name collision between the two variants — they just share helper code.
- Generalized: `BackendUtils.get_item_template` hook routes by variant family. cwv_es_musket items → musket_template / _melee; cwv_es_musket_old items → old_musket_template / _melee. Detection via template field OR backend_id prefix (`^cwv_es_musket_old_` is checked BEFORE `^cwv_es_musket_` because the latter is a substring of the former).
- Extended: `spawn_inventory_unit` hook gate now accepts `Weapons.old_musket_template_melee`. Mode detection (`_mode = ... and "melee" or "ranged"`) now treats either melee template as melee, so 1P-MELEE transform tunings apply correctly when the user toggles into bayonet stance.
- Bayonet child-unit spawn for old musket stays SUPPRESSED (v0.1.278 gate intact) — the custom mesh has a bayonet baked into the FBX so no extra unit is needed.
- Cross-slot inventory inject (v0.1.300) still excludes `cwv_es_musket_old` items, so the inventory grid still shows the variant only in the ranged slot.

## 0.1.300-dev (2026-05-11) — Old Musket: ranged-only with dedicated template; original Musket on ice
- User direction: Old Musket is **ranged-only**. Disable melee slot, drop the stance toggle / bayonet. Stat modifiers (vs vanilla `handgun_template_1`, not stacked on existing musket changes):
  - Reload time: **1.5x vanilla** (50% slower)
  - Ranged power: **1.5x vanilla** (+50% via cloned damage profile `cwv_old_musket_shot`)
- New: `Weapons.old_musket_template` — direct clone of `handgun_template_1` + the two modifiers above. No stance toggle, no bayonet attach. Variant entry switched from `template = "musket_template"` → `template = "old_musket_template"`.
- cwv_es_musket variant (vanilla rifle + scaling + stance toggle) **put on ice** as a backup idea per user request. Variant entry commented out (not deleted). Supporting code (musket_template / musket_template_melee / bayonet system) is still in place so the variant can be revived by just uncommenting the entry — no code restoration needed.
- Three call-site updates to keep the new template working with existing infrastructure:
  1. **spawn_inventory_unit hook gate** now accepts `Weapons.old_musket_template` (in addition to the two musket templates) so texture binding, transform tuning, and FX-proxy spawn still fire for the old musket.
  2. **BackendUtils.get_item_template hook** short-circuits for `template == "old_musket_template"` and the `^cwv_es_musket_` backend_id pattern now excludes `^cwv_es_musket_old_` — without these, the stance lookup would swap old-musket items back to the on-ice musket_template at every equip.
  3. **Cross-slot inventory inject** (BackendInterfaceItemPlayfab.get_filtered_items hook) now skips items matching `^cwv_es_musket_old`. Old musket is ranged-only; vanilla's `slot_type == ranged` filter already includes it. Inject would have wrongly placed it in the melee grid too.
- Description updated to drop melee references. 1P-MELEE transform state still lives in code (and the `cwv_om_*_1p_m` commands still work) but doesn't trigger for the old musket — useful if melee slot is ever reconsidered.

## 0.1.299-dev (2026-05-11) — Old Musket: 1P MELEE transform defaults locked in
- User-confirmed 1P MELEE values from live-tune: pos `(0, 0.06, 0)`, rot axis `(0, 1, 0) @ -90°` (pure Y-axis), scale identity. Defaults now bake those values via `QuaternionBox(Quaternion.axis_angle(...))`. 3P remains at identity (works without adjustment).

## 0.1.298-dev (2026-05-11) — Old Musket: wrap rotation state in QuaternionBox (cross-frame storage)
- User report: "We seem to have lost the first person settings for ranged" — gun perpendicular to expected orientation and on its side. v0.1.295's 1P-RANGED rotation values WERE confirmed working in v0.1.296; v0.1.297 inadvertently broke them.
- Root cause: v0.1.297 stored `Quaternion.axis_angle(...)` directly in a global, but Stingray's `Quaternion` type is a **stack-allocated temporary** valid only within the frame it was created. After the frame ended, the memory got recycled by other Quaternion operations, and our stored value pointed at garbage / a different rotation. Vanilla VT2 pattern (e.g., `bt_attack_action.lua:99`, `ai_bot_group_system.lua:460`): use `QuaternionBox(rotation)` to box for long-term storage, `:unbox()` to retrieve a fresh raw Quaternion when needed.
- Fix: every place that STORES a rotation now wraps in `QuaternionBox(...)`; every place that READS (apply, show) calls `:unbox()`. Helper `_unbox_or_identity(boxed)` returns `boxed:unbox()` or `Quaternion.identity()` for nil. The mul commands unbox the current state, multiply with the new raw quaternion, and re-box the result.
- Same rule applies to `Vector3` in principle, but our pos/scale state is stored as Lua tables `{x, y, z}` and converted to `Vector3(...)` at apply time — that's already safe (the Vector3 is created and immediately consumed, no cross-frame storage).

## 0.1.297-dev (2026-05-11) — Old Musket: composable rotations (`rotmul`, `eul`) + Quaternion state
- Refactored rotation state from `{ax, ay, az, radians}` axis-angle table → `Quaternion` (or nil = identity). Single axis-angle can't represent composed rotations, but Quaternions compose via `Quaternion.multiply`. Defaults preserved: 1P-RANGED still defaults to `Quaternion.axis_angle(Vector3(1,1,-1), -π/2)` from v0.1.295.
- Three rotation operations per bucket now (1P-RANGED / 1P-MELEE / 3P = 9 commands):
  - `cwv_om_rot_<bucket> <ax> <ay> <az> <deg>` — SET (replace current with single axis-angle)
  - `cwv_om_rotmul_<bucket> <ax> <ay> <az> <deg>` — MULTIPLY current rotation by a new axis-angle (compose on top)
  - `cwv_om_eul_<bucket> <x_deg> <y_deg> <z_deg>` — SET from Euler XYZ degrees
- `cwv_om_show` now decomposes the rotation via `Quaternion.to_euler_angles_xyz` so the echoed values are readable (`euler_xyz=(x°, y°, z°)`).
- Composition use case: keep current base orientation (e.g. axis (1,1,-1) @ -90°) and add a barrel roll via `cwv_om_rotmul_1p_r 0 0 1 90` (try X/Y/Z axes — whichever rolls the gun the way you want is the barrel axis after the base rotation).

## 0.1.296-dev (2026-05-11) — Old Musket: FX-proxy linked to player hand (fixes muzzle origin)
- User report: muzzle FX appeared "under the camera in first person, stomach in 3P".
- Root cause: v0.1.293–295 linked the FX proxy to `our_unit`'s root via `World.link_unit(world, proxy, 0, our_unit, 0)`. The proxy then inherited our visible mesh's transform chain, including the rotation `(1,1,-1) @ -90°` we applied to align the visible mesh with the player's grip. That rotation flips the rifle's "forward" axis — so the proxy's `fx_muzzle` node (offset forward in the vanilla rifle FBX) ended up pointing toward the camera in 1P or back toward the chest in 3P. Flow events spawned particles at that misaligned muzzle world position.
- Fix: link the proxy directly to `owner_unit_1p` / `owner_unit_3p` at the `j_rightweaponattach` bone — the same attachment node vanilla `AttachmentNodeLinking.rifles` uses for the rifle's root. The proxy now gets vanilla's natural pose (independent of our visible mesh's reorientation), so its `fx_muzzle` ends up where a vanilla empire-handgun's muzzle would naturally be: in front of the player's hand. Muzzle flash + bullet trail + casing eject all spawn from there.
- Reset proxy's local transform to identity (`set_local_position/rotation/scale` to identity / 1) after linking, since spawn pos+rot would otherwise be preserved as the local-relative-to-parent transform and shift node positions.
- Trade-off: FX emission point follows vanilla rifle's silhouette, not our visible mesh's silhouette (longer barrel etc). If the FX visibly mismatches the visible barrel end, we can offset the proxy's local position to shift the muzzle forward. Tunable via a future `cwv_om_fx_offset` command if needed.

## 0.1.295-dev (2026-05-11) — Old Musket: 1P transform locked in for ranged stance; split state by mode
- User-confirmed 1P ranged values dialed in: pos `(0, 0.62, 0)`, rot axis `(1, 1, -1) @ -90°`, scale `(1, 1.2, 1.4)`. Default 1P-ranged constants now hold those values.
- Restructured transform state from (1P / 3P) to (1P-RANGED / 1P-MELEE / 3P) since the musket stance toggle switches between `musket_template` (ranged rifle pose) and `musket_template_melee` (polearm pose) with different visual requirements per stance.
- The spawn_inventory_unit hook reads `item_template` to determine mode (`item_template == Weapons.musket_template_melee → "melee"`, else `"ranged"`) and routes to the correct state bucket via the new `_apply_old_musket_transform(unit, perspective, mode)` signature.
- 10 commands now (3 ops × 3 buckets + show):
  - `cwv_om_pos_1p_r / _1p_m / _3p <x> <y> <z>`
  - `cwv_om_rot_1p_r / _1p_m / _3p <ax> <ay> <az> <degrees>`
  - `cwv_om_scale_1p_r / _1p_m / _3p <x> <y> <z>`
  - `cwv_om_show` — echoes all three buckets
- 1P MELEE state currently identity (placeholder); user will tune live and persist desired values after that.

## 0.1.294-dev (2026-05-11) — Old Musket: FX-proxy fixes — spawn args + flow_event/set_flow_variable hooks
- User report after v0.1.293: still no sound or visual effects.
- Investigation:
  1. `Managers.state.unit_spawner:spawn_local_unit(unit_name, position, rotation, material)` requires position+rotation. v0.1.293 called with no args so `World.spawn_unit(world, name, nil, nil)` likely errored silently inside the pcall. Now passes the parent mesh's current world position/rotation as initial placement (then `World.link_unit` parents to mesh root so it tracks).
  2. Added diagnostic logging (`[cwv old-musket fx] proxy spawned: ...`) so the next mission load reveals whether spawn succeeded.
  3. Added hooks on `Unit.flow_event` and `Unit.set_flow_variable` (in addition to `Unit.node` / `Unit.has_node` from v0.1.293). `ActionHandgun:client_owner_post_update` fires `Unit.flow_event(weapon_unit, "lua_bullet_trail")` on the weapon — this drives bullet-trail particles via the rifle's compiled flow graph. Our custom mesh has no flow graph so the call no-ops. Hooks redirect: when the targeted unit is in our proxy table, forward the call to the proxy (which has the full vanilla flow graph baked in).
- Note: `action_base.lua:5` does `local unit_flow_event = Unit.flow_event` at module load time — captured BEFORE our hook installs, so calls THROUGH that local bypass our hook. But action_base's three `unit_flow_event(...)` callsites all target `owner_unit` or `first_person_unit` (the player's body units), not the weapon. Weapon-targeted flow events come from action_handgun.lua which calls `Unit.flow_event(weapon_unit, ...)` directly through the table — our hook catches those.

## 0.1.293-dev (2026-05-11) — Old Musket: live-tune commands, previewer textures, FX-proxy (approach A)
- **Live-tune commands** (replacing the v0.1.286-deleted set, now per-perspective):
  - `cwv_om_pos_1p / cwv_om_pos_3p <x> <y> <z>` — translation
  - `cwv_om_rot_1p / cwv_om_rot_3p <ax> <ay> <az> <degrees>` — axis-angle rotation
  - `cwv_om_scale_1p / cwv_om_scale_3p <x> <y> <z>` — local scale
  - `cwv_om_show` — echo current 1P and 3P values
  - State stored in module-globals (`_CWV_OLD_MUSKET_POS_1P` etc.) at file top. Weak-keyed tracking sets `_CWV_OLD_MUSKET_UNITS_1P/3P` populated by the GearUtils.spawn_inventory_unit hook so command changes propagate to all currently-spawned instances (including the inventory previewer). Defaults are identity (FBX-authored transform).
- **HeroPreviewer texture binding**: extended the existing `_cwv_spawn_item_post` callback. When the previewer spawns cwv_es_musket_old, walk the right-hand unit and apply textures (same `_apply_old_musket_textures` helper as the in-mission path). Also tracks for live-tune + applies current transform. Fixes the inventory character-preview UI showing a white mesh.
- **Approach A — hidden vanilla rifle for sound/VFX**: vanilla actions look up named nodes like `fx_muzzle` / `j_hammer` / `j_trigger` on the weapon unit. Our custom FBX has none of those nodes baked in, so muzzle flash, smoke, casing-eject, and Wwise sound emission all no-op (or error). Fix:
  1. After our custom mesh spawns, spawn a vanilla `wpn_empire_handgun_t1` 1P + 3P unit via `Managers.state.unit_spawner:spawn_local_unit` (no extensions).
  2. `World.link_unit` the proxy as a child of our mesh's root, then `Unit.set_unit_visibility(proxy, false)` so it never renders.
  3. Store `our_unit → proxy_unit` in `_CWV_OLD_MUSKET_FX_PROXY` (weak-keyed).
  4. Hook `Unit.node` and `Unit.has_node` globally: when the unit being queried is in our proxy table and the requested name doesn't resolve on it, redirect to the proxy's node. Every other Unit.node call in the game is untouched (proxy-table lookup is a fast weak-table read; no proxy entry → straight passthrough).
  5. Extended `GearUtils.destroy_wielded` hook to call `_destroy_old_musket_fx_proxy` so the hidden rifle is `mark_for_deletion`'d alongside its parent.
  - Captured the pre-hook `Unit.has_node` reference BEFORE installing the hook so the Unit.node hook can probe-our-mesh-first without re-entering the has_node hook chain (avoids spurious "either has it → use orig on mesh that doesn't have it → engine fatal").
- Expected behavior: muzzle flash, shot sound, reload click, casing eject, all wired through Unit.node-based action code should now fire from the right world position (our mesh's hand-attached position, since the hidden rifle is linked to its root). Flow-event-driven FX baked into the vanilla rifle's compiled unit also fire normally since the proxy is a real unit. Anything that uses a HARDCODED-by-handle reference to a specific unit ID wouldn't be redirected, but those are rare in VT2 action code.

## 0.1.292-dev (2026-05-11) — Old Musket: bind custom PBR textures at runtime (mesh was white)
- After v0.1.286's architectural rewrite, mesh attached/rendered correctly but appeared opaque white. Root cause: switching to the LA pattern dropped our custom `.material` file (which had bound our PBR textures at compile time). The engine doesn't auto-resolve `data.mat_to_use` to a material+textures binding — that field is just metadata that LA's runtime code reads. Without a `materials = {}` block AND without runtime texture binding, the FBX-embedded material on our mesh stayed at default white.
- The textures are already shipped at `textures/cwv_es_musket_custom/` (albedo, normal, metallic, AO, roughness — all PNG+`.texture`). They were referenced by the deleted `.material` file in v0.1.285 and earlier.
- Fix (mirrors LA's `apply_texture_to_all_world_units` in `utils/funcs.lua:4`): extended the existing `GearUtils.spawn_inventory_unit` hook. When the spawned weapon's `item_data.backend_id` matches `cwv_es_musket_old`, walk both 1P and 3P units via `Unit.num_meshes` → `Unit.mesh` → `Mesh.num_materials` → `Mesh.material`, and call `Material.set_texture(mat, slot_hash, texture_path)` for the three PBR slots:
  - `texture_map_c0ba2942` (color/albedo) → `cwv_es_musket_custom_albedo`
  - `texture_map_59cd86b9` (normal) → `cwv_es_musket_custom_normal`
  - `texture_map_0205ba86` (MAB) → `cwv_es_musket_custom_metallic`
- Known follow-ups: HeroPreviewer + LootItemUnitPreviewer paths also need this binding for the mesh to appear correctly textured in the inventory UI and skin browser. Adding once in-mission is confirmed via this release.

## 0.1.291-dev (2026-05-11) — Fix: use Unit.has_node (pcall doesn't catch Stingray engine errors)
- Crash on startup with the same `[Script Error]: j_lock` after v0.1.290's filter was supposed to fix it (GUID e72b504c).
- Root cause: v0.1.290 used `pcall(Unit.node, target, "j_lock")` to probe whether the target had the node. But Stingray's `Unit.node` raises an **engine-level fatal** when the name doesn't resolve — pcall doesn't catch these. The "j_lock" string in the error is what `Unit.node` threw; the surrounding pcall was bypassed entirely.
- Fix: replaced the pcall probe with `Unit.has_node(target, name)`, which returns a boolean. Verified pattern in vanilla `ai_bot_group_system.lua:190`: `Unit.has_node(unit, node_name) and Unit.node(unit, node_name) or 0`.
- Memory updated: LA-pattern recipe Part 4 now uses `Unit.has_node` instead of pcall.

## 0.1.290-dev (2026-05-11) — Old Musket: filter attachment_node_linking for rig-less custom mesh
- Crash on equip after our mesh appeared briefly (white/no-texture) then `[Script Error]: j_lock` (GUID 5c21d3b1).
- Root cause: vanilla `GearUtils.link_units` iterates `AttachmentNodeLinking.rifles.first_person.wielded`, which contains 4 entries — 3 link player-hand component bones (`j_rightweaponcomponent1/2/3`) to weapon rig nodes (`j_lock`, `j_hammer`, `j_trigger`). Our FBX has no skeleton (just mesh geometry), so `Unit.node(target, "j_lock")` errors.
- Fix: hooked `GearUtils.link_units`. Probes the target unit by attempting `Unit.node(target, "j_lock")` — if the call errors, the target is a rig-less mesh (our custom unit) and we filter the linking table to entries whose target resolves on it (always the `target = 0` root-node entry, plus any named-node entries that happen to exist). The root entry is what physically attaches the weapon to the hand; the others are decorative finger-pose links that only matter for vanilla rifles with the full rig.
- Live verification: weapon should now attach to the right hand without crashing. Finger-on-trigger/hammer pose will be slightly off (the player's component-bones won't be locked to weapon parts), but the weapon will be wielded correctly.

## 0.1.289-dev (2026-05-11) — Fix: drop unloadable `display_shield_spear` force-load
- Crash on startup: `[Engine Error]: Resource '#ID[3445b9bc494ef8b3]' was not found!` (GUID 84a074da). Hash reverses to `units/weapons/weapon_display/display_shield_spear` (per `reference_vt2_hash_reverse_lookup.md`).
- Root cause: v0.1.288's `_force_load_javelin_shield_melee_assets` tried to force-load the display unit path via `Managers.package:load`, but display units are bundled INSIDE other packages — not registered as per-asset loadable paths in `scripts/network_lookup/inventory_package_list.lua`. The async load fatals with "Resource not found", which bypasses the surrounding synchronous pcall (engine error, not a Lua error).
- This is the **same failure mode as v0.1.224** (which dropped `display_2h_spears_wood_elf`). Generalized rule: only force-load paths that appear in `inventory_package_list.lua`. `1h_spear_shield` state machine is on line 252 → loadable. `display_shield_spear` is not in the list → not loadable.
- Fix: dropped `display_shield_spear` from the force-load list. Only `1h_spear_shield` state machine is force-loaded now.

## 0.1.288-dev (2026-05-11) — New variant: Tuskgor Javelin & Shield (Kruber, stance toggle, v1)
- Added: `cwv_es_javelin_shield` for Empire Soldier (Kruber, all careers). Ranged stance is identical to `cwv_es_javelin` (Tuskgor Javelin throw — boar spear visual, 10 ammo, sticks-in-walls pickup, etc.). Weapon special key toggles to a 1H spear+shield melee stance with `range_mod = 1.15` (≈0.85x of vanilla 1.35). Same stance-toggle recipe as `cwv_es_musket` (see `reference_cwv_stance_toggle_recipe.md`).
- Implementation:
  - Two new templates registered on `Weapons`: `cwv_javelin_shield_template_ranged` (clone of `tuskgor_javelin_template`) and `cwv_javelin_shield_template_melee` (clone of `one_handed_spears_shield_template`). Each replaces `action_three` with the stance-toggle dummy and gets `lookup_data` attached on every sub-action.
  - Per-item stance flag at `item_data.mod_data.cwv_javelin_shield_stance` ("ranged" | "melee", default ranged). Ammo fraction persisted on `mod_data.cwv_javelin_shield_ammo_fraction` so ranged→melee→ranged keeps the same ammo count.
  - Toggle helper `_toggle_javelin_shield_stance_and_rewield`: flip flag → capture ammo (or restore from mod_data when wielded slot has no ammo extension) → `destroy_slot` → `add_equipment` (5th arg = ammo fraction) → `wield`.
  - New `mod:hook("BackendUtils", "get_item_template", ...)` block for the javelin+shield items — separate from the musket hook, both chain via VMF.
  - Force-loaded `state_machines/melee/1h_spear_shield` and `weapon_display/display_shield_spear` so the first ranged→melee toggle doesn't crash "Resource not loaded" on Kruber's loadout (same pattern as `_force_load_musket_melee_assets`).
- v1 limitation: shield not visually mounted in melee stance. The IML keeps the Tuskgor rig (`right=invisible, left=boar spear, ammo=invisible`) and IML unit fields win over the melee template's defaults in `GearUtils.create_equipment`. Block mechanics (shield_block, block_angle 120, outer_block_angle 360) inherited from the spear+shield template DO work — just no visible shield mesh. v2 polish: spawn a shield child unit on melee toggle like the bayonet pattern.
- **DoD:** Universal gate not fully walked (G-RANGED inherited from existing Tuskgor Javelin, G-STANCE matches musket recipe). Live verification needed: equip in modded realm, confirm ranged-stance behaves like vanilla Tuskgor Javelin, press special to toggle to melee, verify spear+shield 1P + 3P animations play on Kruber's skeleton (likely 3P holes — Empire skeleton has spear+shield events natively? requires `force3p` probe). Visible-shield deferred to v2.

## 0.1.287-dev (2026-05-11) — Old Musket: register custom paths in NetworkLookup.inventory_packages
- Crash on equip: `[NetworkLookup.lua] Table inventory_packages does not contain key: units/cwv_es_musket_custom/cwv_es_musket_custom_3p`.
- Root cause: vanilla code indexes `NetworkLookup.inventory_packages[unit_path]` during equip to get a network sync index. That table has a strict `__index` metamethod that errors on unknown keys (same family as `NetworkLookup.breeds` per `feedback_vt2_strict_lookup_rawget.md`).
- Fix: at mod-init time, alias our two custom unit paths to the vanilla rifle's existing network indices via direct table assignment. Forward direction only — we don't hijack the reverse index→path mapping like LA's skin-replacement code does, because cwv variants don't replace vanilla weapons globally.
- Pattern verified in LA source `utils/funcs.lua:124-128`. Memory `reference_la_custom_mesh_pattern.md` updated with NetworkLookup step as a new mandatory Part 4 of the LA recipe.

## 0.1.286-dev (2026-05-11) — Old Musket: LA-pattern direct mesh spawn (FP rendering fix)
- Complete architectural rewrite based on Loremaster's Armoury's reference implementation (dalokraff/Loremasters-Armoury). The v0.1.277-285 overlay system (World.spawn_unit + link_unit + force-hide vanilla + visibility sync) is GONE. The new flow:
  - **`right_hand_unit` is our custom mesh path** (reverted from v0.1.277's vanilla-rifle path). Vanilla GearUtils pipeline spawns it directly, which gives it the engine's first-person rendering pipeline — no shadow in FP, correct depth ordering, draws under the FP hand model.
  - **`.unit` file rewritten to LA's pattern**: NO `materials = {}` block (which compile-validates against SDK and fails for vanilla paths). Instead a `data = { mat_to_use = "<vanilla material path>", color_slot, norm_slot, MAB_slot, mat_slots }` block. The compiler doesn't validate `data` field paths, but the compiled .unit ends up referencing the vanilla material — proven by extracting our build and finding the vanilla path embedded as a string. 1P uses 1P vanilla material; 3P uses `_3p` variant. `shadow_caster = false` on the 1P (no FP weapon shadow).
  - **3 PackageManager hooks** (load / unload / has_loaded) scoped to our two unit paths. When the engine tries to package-load `units/cwv_es_musket_custom/...` (no sibling `.package` file exists), our hooks silently no-op (load/unload) or report success (has_loaded). The unit data is already in our master bundle via the `unit = ["units/*"]` glob, so World.spawn_unit can find it by path. This is verbatim LA's mechanism from their utils/hooks.lua.
- Deleted: `_old_musket_overlay_pairs`, `_attach_old_musket_overlays`, `_spawn_and_link_old_musket`, `_detach_old_musket_overlay`, `_sync_all_old_musket_overlays_visibility`, `_apply_old_musket_transform`, `_reapply_old_musket_transforms_to_all`, `_CWV_OLD_MUSKET_*` constants, `_CWV_OLD_MUSKET_DEBUG_MODE`. Console commands `cwv_om_pos / cwv_om_rot / cwv_om_scale / cwv_om_show / cwv_om_debug / cwv_om_euler` all removed.
- Deleted on-disk: `units/cwv_es_musket_custom/cwv_es_musket_custom.material` (no longer needed — we reference vanilla material), `cwv_es_musket_custom.package` / `_3p.package` (LA's PackageManager hooks make these unnecessary), stale `0e9fc1f2f551a8e8.mod_bundle` / `fe7ed4530b1ccd6a.mod_bundle` from previous sibling-package experiments.
- Removed from master `.package`: `material = ["units/*"]` and `package = [...]` blocks. Just `lua`, `unit`, `texture` now.
- Bayonet suppression for cwv_es_musket_old (v0.1.278) retained — the custom mesh has its own bayonet built in.
- Side effect: the cwv_es_musket_old model will initially appear with vanilla rifle textures (because we reference the vanilla rifle's material). To use our custom PBR textures, we need to follow LA's full pattern and call `Material.set_texture(mat, color_slot, our_texture)` on the unit's meshes after spawn. That's a follow-up; the rendering fix is the priority.

## 0.1.285-dev (2026-05-11) — Old Musket: debug-mode toggle for FP alignment tuning
- Added `cwv_om_debug <0|1|2>` console command + `_CWV_OLD_MUSKET_DEBUG_MODE` global. Lets user see the vanilla rifle alongside (mode 2) or instead of (mode 1) the overlay for visual alignment.
  - mode 0 (default): overlay shown, vanilla hidden — normal
  - mode 1: overlay hidden, vanilla shown — looks like no mod, reveals where hand+rifle actually are
  - mode 2: BOTH shown — for tuning overlay transform to match the vanilla rifle's grip/orientation
- Modified all force-hide-vanilla and overlay-visibility sites (spawn + 3 sync hooks + sync function) to respect the debug-mode flag rather than unconditionally hiding/showing.
- Why: in 1P FP view, our overlay's render-layer mismatch makes it draw on top of the hand, so the user can't see whether the overlay is positioned correctly relative to the hand. Mode 2 reveals the vanilla rifle position so the user can dial the overlay transform to match.

## 0.1.284-dev (2026-05-11) — Old Musket: bake in 3P-confirmed transform
- User-confirmed 3P transform baked in as new defaults (works for both melee and ranged slot grips):
  - `_CWV_OLD_MUSKET_LOCAL_TRANSLATION = { 0, 0.625, -0.01 }`
  - `_CWV_OLD_MUSKET_LOCAL_ROTATION_AXIS = { 1, 1, -1 }`
  - `_CWV_OLD_MUSKET_LOCAL_ROTATION_ANGLE = -math.pi / 2`
- Console commands `cwv_om_pos` / `cwv_om_rot` / `cwv_om_scale` / `cwv_om_show` remain for further live tuning if 1P FP-view needs different values.

## 0.1.283-dev (2026-05-11) — Old Musket: force-hide vanilla rifle on every sync tick
- User reported the vanilla rifle still rendering alongside our overlay. v0.1.281's `Unit.set_unit_visibility(rifle, false)` at spawn time DID work momentarily, but the game's own wield / show_first_person_inventory / show_third_person_inventory code paths re-enable the rifle's visibility shortly after.
- Fix: in every sync hook (`show_first_person_inventory`, `show_third_person_inventory`, and `_sync_all_old_musket_overlays_visibility`), after the engine sets the vanilla rifle visible, immediately force-hide it again if it has an overlay attached. Gated on `_old_musket_overlay_pairs[rifle]` being present so only overlay-attached rifles are forced — vanilla cwv_es_musket and other weapons unaffected.

## 0.1.282-dev (2026-05-11) — Old Musket: tunable transform + live-tune commands
- Added tunable globals: `_CWV_OLD_MUSKET_LOCAL_TRANSLATION`, `_CWV_OLD_MUSKET_LOCAL_ROTATION_AXIS`, `_CWV_OLD_MUSKET_LOCAL_ROTATION_ANGLE`, `_CWV_OLD_MUSKET_LOCAL_SCALE` (starting baseline: zero translation, no rotation, scale 1). Applied to the overlay's LOCAL frame after linking to the vanilla rifle's root node.
- New helpers: `_apply_old_musket_transform(overlay)` (single-unit) and `_reapply_old_musket_transforms_to_all()` (iterates `_old_musket_overlay_pairs`).
- Four console commands for live tuning without rebuild:
  - `cwv_om_pos <x> <y> <z>` — set local translation
  - `cwv_om_rot <ax> <ay> <az> <degrees>` — set rotation axis + angle
  - `cwv_om_scale <x> <y> <z>` — set scale
  - `cwv_om_show` — echo current values
- After each set-command, transforms are re-applied to all currently-attached overlays so you see the result immediately.

## 0.1.281-dev (2026-05-11) — Old Musket: consolidate visibility-sync hooks + hide 1P by default
- v0.1.280 spawn succeeded for both 1P and 3P overlays. Log: `World.spawn_unit: ok=true` for both, `link: ok=true`, `hide vanilla: ok=true`. But user reported "two muskets — one through the chest, one floating perpendicular".
- Root cause #1: VMF's `mod:hook_safe` refuses to register a second callback on the same (Class, method) pair. Log evidence: `WARNING: Attempting to rehook active hook [show_first_person_inventory]` (× 3 for the three hooks). The overlay's three sync hooks were silently shadowed by the bayonet's pre-existing hooks on the same methods. Documented in memory `feedback_vmf_hook_safe_no_chain.md` — I should have remembered this when adding the duplicate hooks.
- Fix #1: deleted the three overlay sync hooks; extended the bayonet's three callbacks to ALSO sync overlays in the same callback. Now there's exactly one mod:hook_safe per (Class, method).
- Root cause #2: `_sync_all_old_musket_overlays_visibility` was declared as `local function` BELOW the bayonet's `_wield_slot` callback that now calls it — same forward-ref pattern that bit v0.1.279. Switched to global assignment (`_sync_all_old_musket_overlays_visibility = function(...)`).
- Root cause #3: 1P overlay defaulted to visible after spawn. In 3P contexts (inventory previewer, other players' camera), the 1P RIFLE isn't rendered but the linked overlay was rendering anyway because nothing was hiding it. Added `Unit.set_unit_visibility(overlay_1p, false)` right after attach so the 1P overlay starts hidden; `show_first_person_inventory(true)` hook reveals it when the local player enters FP view.

## 0.1.280-dev (2026-05-11) — Old Musket: fix forward-reference bug (the actual cause)
- v0.1.279 diagnostic build pinpointed the real issue. Log: `[cwv old-musket] _attach errored: ...lua:3414: attempt to call global '_attach_old_musket_overlays' (a nil value)`.
- Classic Lua forward-ref bug — exactly what `feedback_lua_forward_reference.md` warns about. `_attach_old_musket_overlays` and `_spawn_and_link_old_musket` were declared as `local function` BELOW the GearUtils.spawn_inventory_unit hook callback that calls them. Lua parses the file top-down — at the call site (line 3414), no local of that name was in scope yet, so Lua compiled the reference as a GLOBAL access. The later `local function` definition created a local, not a global, so the runtime global lookup returned nil.
- Fix: switched both definitions from `local function NAME(...)` to `NAME = function(...)` (global). Globals are resolved at runtime each invocation, so they work for forward refs. Matches the existing pattern of `_old_musket_overlay_pairs` and `_detach_old_musket_overlay` which were already globals.
- v0.1.277 and v0.1.278 both had this bug — every previous "the gate is failing" theory was wrong. The gate ALWAYS passed (v0.1.279 log proved it). The call to `_attach_old_musket_overlays` was failing because the symbol didn't resolve. v0.1.278 wrapped the call in `pcall` which swallowed the error silently — that's why we never saw the failure until v0.1.279 switched to xpcall with traceback.
- Sanity check: Methodology that actually worked = (1) read log evidence first, (2) form hypothesis from evidence, (3) instrument code to fail loudly, (4) read NEW evidence, (5) apply targeted fix. Steps 1-4 are non-negotiable before fixing.

## 0.1.278-dev (2026-05-11) — Old Musket: fix overlay gate + suppress bayonet
- Bug from v0.1.277: gated overlay on `item_data.item_type == "cwv_es_musket_old"`. Console log showed bayonet hook fires (so the spawn_inventory_unit callback runs for our variant) but NO `[cwv old-musket] attach` log line — meaning `item_data.item_type` is NOT "cwv_es_musket_old" at the GearUtils spawn callsite. `item_data` passed in is the BASE `es_handgun` IML entry, not our cwv entry — only the backend_id carries the cwv-specific identifier.
- Switched gate to `item_data.backend_id:match("^cwv_es_musket_old")` — canonical CWV detection per `feedback_cwv_backend_id_lookup.md`. Also added a debug log line so any future gate-failure shows backend_id/item_type/name values for diagnosis.
- Also suppressed bayonet attach for cwv_es_musket_old: the custom mesh has its own bayonet baked into the model, so the floating vanilla-sword bayonet was incorrect. Gate added BEFORE `_attach_musket_bayonets` call.
- Honest framing: v0.1.277 was a real bug (wrong field used for detection). Not malicious sleight-of-hand — I drew from `_build_entry` setting `entry.item_type = def.item_type or def.item_key` and assumed that field flowed to the in-mission item_data. It doesn't: MIL preserves item_type on the cwv ENTRY in ItemMasterList, but when the engine resolves a backend item to its IML entry for spawn, it follows entry.name (= "es_handgun" inherited from base) and lands on the base entry. backend_id is the only cwv-specific identifier that survives the lookup chain.

## 0.1.277-dev (2026-05-10) — Old Musket: LA-style vanilla-overlay architecture
- Re-enabled `cwv_es_musket_old` with `right_hand_unit = "units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1"` (vanilla rifle). This makes the world previewer / GearUtils package-load calls succeed since they're now hashing a vanilla path that has a vanilla bundle.
- Added the **custom-mesh overlay system**: at spawn time we hide the vanilla rifle unit (`Unit.set_unit_visibility(rifle, false)`) and spawn `units/cwv_es_musket_custom/cwv_es_musket_custom[_3p]` linked to the rifle's root node so the overlay inherits all transform/animation. Player sees the custom mesh; the vanilla rifle is the invisible "anchor" the game's behaviour systems operate on. Mirrors the bayonet pattern but for the whole weapon mesh.
- Detection: gate on `item_data.item_type == "cwv_es_musket_old"`. `_build_entry` (line 6532) sets `entry.item_type = def.item_type or def.item_key`, so the explicit `item_type = "cwv_es_musket_old"` on the variant def becomes the IML entry's item_type. cwv_es_musket (different variant) has `item_type = "cwv_es_musket"` and skips the overlay (its vanilla rifle mesh is its intended visual).
- Visibility sync, orphan prune, destroy_wielded cleanup all mirror the bayonet's structure. Tracked in `_old_musket_overlay_pairs` (weak-keyed by vanilla rifle).
- The custom unit data is in our master bundle (compiled by `unit = ["units/*"]` glob in the master `.package`). After mod boot, `World.spawn_unit(world, "units/cwv_es_musket_custom/cwv_es_musket_custom", ...)` succeeds by path because the unit resource is in the engine's live resource table — even though `Application.resource_package(<path>)` cannot find a *package* at that path.
- Inventory previewer (HeroPreviewer) shows the VANILLA rifle for the Old Musket variant; the overlay only fires in-mission. TODO: also overlay in the inventory previewer so the player can tell which musket is which from the inventory grid.
- Dead-weight cleanup deferred: the two sibling `.package` files (`cwv_es_musket_custom.package` and `_3p.package`) and the `0e9fc1f2f551a8e8.mod_bundle` / `fe7ed4530b1ccd6a.mod_bundle` files are inert but still compiled. Will remove in a follow-up once the overlay is verified working.

## 0.1.276-dev (2026-05-10) — Disable cwv_es_musket_old until vanilla-overlay architecture
- Commented out the `cwv_es_musket_old` variant entry. Reverted `.mod` `packages = {...}` list back to just the master. Stops the crash.
- The `units/cwv_es_musket_custom/` files (FBX, unit, material, textures, sibling packages) remain on disk and in the bundle — they're inert dead weight until the variant comes back, but cheap to keep in case we revisit. Players who already have this v0.1.276 deploy lose access to "Old Musket" entirely (no crash, just no item).
- See "Old Musket crash debugging" log below for the full failure analysis and why this approach was needed. Short version: VT2's `Application.resource_package(path)` only resolves paths that have a bundle file in the game's `bundle/` folder (vanilla), not mod-shipped sibling bundles, and the world previewer hardwires a `package:load(right_hand_unit .. "_3p")` call we can't avoid without per-call hooks.

## Old Musket crash debugging — running log of attempts and failures

The crash `[Engine Error]: Resource '#ID[0e9fc1f2f551a8e8]' was not found!` (hash decodes to `units/cwv_es_musket_custom/cwv_es_musket_custom_3p`) has resisted every fix from v0.1.272 through v0.1.275. Documenting each attempt so I stop re-trying things that didn't work.

| Version | Hypothesis | What I did | Result |
|---------|-----------|------------|--------|
| 0.1.272 | FBX-baked material binding was unresolvable | Authored `.material` file cloning standard.material PBR shader graph, bound textures, renamed FBX material to `rifle_mat`, updated `.unit` materials block | Same crash, same hash |
| 0.1.273 | The hash decodes to `_3p` — engine auto-resolves a 3P sibling unit and it didn't exist | Duplicated `cwv_es_musket_custom.fbx`/`.unit` to `_3p` variants; both ship in bundle | Same crash, same hash |
| 0.1.274 | The previewer calls `package:load(path)` which expects a `.package` resource at that path, not a `.unit` | Authored `cwv_es_musket_custom.package` and `cwv_es_musket_custom_3p.package` files; added `package = [...]` to master `.package` so they compile | Same crash. .package resources DO compile into bundle (verified: `0E9FC1F2F551A8E8.package` 125 B exists in master bundle). |
| 0.1.275 | The sibling-package bundles need to be registered via the `.mod` file's `packages = {...}` list, not just compiled. Pattern verified from `MorePlayers2` mod which ships 2 packages | Added the two sibling package paths to `character_weapon_variants.mod` `packages = {...}` | Same crash. Log confirms v0.1.275 booted cold. NO `[PackageManager] Load: units/cwv_es_musket_custom/...` log line at startup, meaning the engine isn't loading them. |

### What we now know (from VT2 source + Autodesk Stingray research)
- `mod_manager.lua:421` loads `.mod` `packages = {...}` entries via `Mod.resource_package(mod.handle, name)` — a MOD-SCOPED call, takes the mod's handle.
- `package_manager.lua:81/94/105/109/139` (where the crash fires) uses `Application.resource_package(name)` — a GLOBAL call, no mod handle.
- These appear to be different resource namespaces. Adding a package to the .mod list registers it as mod-scoped; later code that calls Application.resource_package can't see it.
- The Loremaster's Armoury mod (ships 104 custom unit resources) does NOT ship sibling `.package` files — it has ONE master `.package` and ONE bundle on disk. Their "custom" unit paths actually REUSE vanilla paths (e.g. `units/weapons/player/wpn_brw_sword_01_t2/wpn_brw_flaming_sword_01_t2_3p`) which already have vanilla bundles in `Vermintide 2/bundle/`. So `Application.resource_package` succeeds because the engine finds the VANILLA bundle for that path. LA never registers a new global package — it piggybacks on existing ones.
- Our path `units/cwv_es_musket_custom/cwv_es_musket_custom_3p` has NO vanilla counterpart, so `Application.resource_package` has nowhere to find it globally.

### Path forward
- The simplest working approach is what LA does: don't ship a NEW package path; reuse a vanilla one. But that doesn't give us a custom mesh that the engine renders for free — LA does mesh overrides via World.link_unit / Material.set_texture / unit-visibility tricks layered on a vanilla base unit.
- Need to either: (a) hook `world_hero_previewer._load_packages` to skip our custom path entirely and rely on the master bundle having pre-loaded the unit, or (b) abandon the custom path and switch to the LA pattern of overlaying on a vanilla unit.

## 0.1.275-dev (2026-05-10) — Old Musket: register sibling packages in the .mod file
- v0.1.274 authored the sibling `.package` files and shipped them as compiled `.mod_bundle` files in the workshop folder, but the same `Resource '#ID[0e9fc1f2f551a8e8]' not found` crash continued. The compiled `.package` resource WAS in the master bundle; what was missing is bundle DISCOVERY.
- Hypothesis (still unverified — based on the `MorePlayers2` mod's pattern, which lists 2 packages in its `.mod`): Stingray only discovers `.mod_bundle` files whose paths are listed in the .mod file's `packages = {...}` table. Sibling packages declared via `package = [...]` in the master `.package` get compiled but their on-disk bundle files aren't registered for runtime hash lookup.
- Added the two sibling package paths to `character_weapon_variants.mod`'s `packages = {...}` list. .mod file size went 606 → 715 bytes (the two entries' overhead).
- Honest framing: I have NOT verified this fix in-game. The user has hit this exact same crash 4 times across v0.1.271 → v0.1.275 because each "fix" was based on a different inference about what the engine wanted. Each was true in part but didn't lift the crash. If this version still crashes, the next step is to compare a vanilla weapon package's bundle layout against ours, or instrument the engine error path to surface the actual resolution failure (not just the hash).

## 0.1.274-dev (2026-05-10) — Old Musket: ship sibling `.package` files (actual fix for the load-time hash crash)
- Fixed (actual actual root cause): the v0.1.273 in-game crash. Console log showed `Managers.package:load("units/cwv_es_musket_custom/cwv_es_musket_custom_3p")` called from `world_hero_previewer.lua:1150` — the inventory previewer treats the right_hand_unit string as a PACKAGE path and asks the package manager to load it. Vanilla weapon directories have a sibling `.package` file at the same path as each `.unit`; we shipped the unit but not the package.
- Engine error format clarification: `[Engine Error]: Resource '#ID[0e9fc1f2f551a8e8]' was not found!` — the hash IS the path hash, but the error means the engine couldn't find a resource of the EXPECTED TYPE at that path. v0.1.273 added the `.unit` resource at hash 0e9fc1f2…; v0.1.274 adds the `.package` resource at the same hash so package loading resolves.
- Authored `units/cwv_es_musket_custom/cwv_es_musket_custom.package` and `cwv_es_musket_custom_3p.package`. Each lists the unit (1P or 3P), the shared material, and all five PBR textures.
- Added `package = [ "units/cwv_es_musket_custom/cwv_es_musket_custom", "units/cwv_es_musket_custom/cwv_es_musket_custom_3p" ]` to the master `character_weapon_variants.package` so the sibling packages get compiled into the bundle.
- Bundle output now includes `0e9fc1f2f551a8e8.mod_bundle` and `fe7ed4530b1ccd6a.mod_bundle` — these are the compiled sibling packages keyed by their path hashes. The master bundle also contains `FE7ED4530B1CCD6A.package` and `0E9FC1F2F551A8E8.package` directly.

## 0.1.273-dev (2026-05-10) — Old Musket: ship the `_3p` unit (real cause of v0.1.271 load crash)
- Fixed (actual root cause): the v0.1.271/272 `[Engine Error]: Resource '#ID[0e9fc1f2f551a8e8]' was not found!` crash. Hash `0e9fc1f2f551a8e8` murmur-reverses to `units/cwv_es_musket_custom/cwv_es_musket_custom_3p` — the engine auto-resolves a 3rd-person sibling for every right_hand_unit (vanilla naming convention: `<unit>` + `<unit>_3p`), and we never authored one.
- Duplicated `cwv_es_musket_custom.fbx`/`.unit` to `cwv_es_musket_custom_3p.fbx`/`.unit` so the 3P resource exists. Both 1P and 3P share `cwv_es_musket_custom.material` (already in the bundle).
- The 1P/3P split bundle now contains 0E9FC1F2F551A8E8.unit (3P, 475 kB) + FE7ED4530B1CCD6A.unit (1P, 475 kB) + FE7ED4530B1CCD6A.material (185 kB). Bundle grew ~310 kB.
- Debugging method (worth keeping): the engine's hashed-ID errors are decipherable. Compute `murmur hash <candidate-path>` (via the bundle unpacker) and compare against the hash from the crash. Build a candidate list of likely paths (auto-derived names, conventionally-named sidecar units, package paths) and brute-force the hash space. v0.1.272 was a wasted iteration because I assumed material binding without verifying via hash reverse-lookup.
- v0.1.272's `.material` work was NOT wasted — without our custom .material, the engine would still error on the FBX's baked-in material slot reference once it got past 3P loading. The full fix is both authoring the .material AND shipping the _3p unit.

## 0.1.272-dev (2026-05-10) — Old Musket: custom-mesh PBR material binding (fix load crash)
- Fixed: load-time crash `[Engine Error]: Resource '#ID[0e9fc1f2f551a8e8]' was not found!` on the v0.1.271 custom-mesh `cwv_es_musket_old` variant. The compiled `.unit` from the user's FBX referenced material slots by names baked in by the FBX importer (the .dae's `01___Default` / `defaultMaterial` slots), which resolved to a resource ID the bundle didn't actually contain.
- Re-exported `cwv_es_musket_custom.fbx` from the source `.dae` via Blender 4.4 headless, collapsing all materials into one single slot named `rifle_mat` (short, predictable, no FBX truncation). Used `units/cwv_es_musket_custom/rename_material.py` (kept on disk at `Downloads/old-musket/` for future re-exports).
- Authored `units/cwv_es_musket_custom/cwv_es_musket_custom.material` — clone of the SDK's `core/stingray_renderer/shader_import/standard.material` PBR shader graph with our texture + variable bindings appended:
  - `textures`: 5 PBR slots (color_map, normal_map, roughness_map, metallic_map, ao_map) pointing at our `textures/cwv_es_musket_custom/cwv_es_musket_custom_*` DXT5 textures from v0.1.271.
  - `variables`: `use_*_map = 1` for all five so the shader actually samples them (defaults are 0 = off).
- Updated `units/cwv_es_musket_custom/cwv_es_musket_custom.unit`: explicit `materials = { rifle_mat = "units/cwv_es_musket_custom/cwv_es_musket_custom" }` block binds the FBX's material slot to our new .material file.
- Added `material = [ "units/*" ]` to the resource package so the .material gets compiled into the bundle.
- Sharp edges learned: (1) FBX exporter truncates material names ~60 chars — keep slot names SHORT and bind to long paths via `.unit` materials block. (2) Vanilla material paths (e.g. `units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1`) are NOT available at SDK compile time even though they exist at runtime — the .unit compiler resolves materials against the source tree, which only sees what's in the SDK + mod folder. Must ship our own .material. (3) Core SDK materials like `core/units/transparent` ARE available at compile time, but are not PBR-textured.

## 0.1.271-dev (2026-05-10) — Musket: multi-instance variants + Old Musket (custom mesh)
- Deleted: `cwv_es_musket_polearm` variant entirely. Was redundant — `cwv_es_musket` already alternates between ranged shoot and bayonet melee via the stance toggle, and the cross-slot UI hook makes it equippable in either slot. No reason for a duplicate variant.
- Added: multi-instance variant support to CWV registration. New `def.instances = N` field creates N backend entries with backend_ids `<key>_001`, `<key>_002`, etc. Optional `def.instance_skins` array pre-applies a different cosmetic skin per instance (nil = the variant's default).
- Changed: `cwv_es_musket` `instances = 2`, `instance_skins = { nil, "cwv_es_musket_aunty_bessie" }`. Player gets TWO Musket items — first with default rifle mesh, second with Aunty Bessie skin pre-applied. Both equippable in either slot (cross-slot UI hook still active), both have stance toggle.
- Added: new variant `cwv_es_musket_old` ("Old Musket") using the custom-mesh compiled from the user's FBX (units/cwv_es_musket_custom/). Same musket_template + stance toggle + cross-slot UI hook as cwv_es_musket. `instances = 2` so the player gets two Old Musket items too. Empty `_type_transforms.cwv_es_musket_old` (no scale tweaks — the custom mesh is the right shape natively).
- Cleaned up the cross-slot filter `_is_cwv_musket_item` to use a single prefix match (`^cwv_es_musket`) covering both variants and all per-instance backend_ids.

## 0.1.270-dev (2026-05-10) — Musket: both variants share display_name "Musket"
- Renamed: `cwv_es_musket_polearm` `display_name` "Aunty Bessie's Musket" → "Musket" (matching `cwv_es_musket`). Both variants now appear as "Musket" in the inventory — the user clarification was "exact same kind of weapon, but one has a different cosmetic equipped". The two are distinguishable only by inventory icon and wielded mesh (default rifle vs Aunty Bessie t3). Same template, same trait, same description, same stats — they're the same item with different default cosmetics.

## 0.1.269-dev (2026-05-10) — Musket: unify both as ranged-slot items
- Changed: `cwv_es_musket_polearm` `base_weapon` from `es_2h_heavy_spear` (melee-slot inheritance) to `es_handgun` (ranged-slot inheritance) per user "make them both ranged musket items". Both musket items are now ranged-slot in IML — no "the melee one" and "the ranged one" distinction. The cross-slot UI hook from v0.1.268 makes both appear in BOTH slot inventory grids.
- Renamed: `display_name` "Bayoneted Musket" → "Aunty Bessie's Musket" (slot-neutral). Both descriptions now mention "Equippable in the melee or ranged slot".
- The v0.1.260 melee tooltip workaround on `musket_template` (max_fatigue_points etc.) and v0.1.265/267 defensive WeaponSpreadExtension hooks stay in place — harmless if unused, robust if any future variant ends up in a different slot.

## 0.1.268-dev (2026-05-10) — Musket cross-slot inventory: appears in BOTH slot grids
- Added: both `cwv_es_musket` (declared slot_type ranged) and `cwv_es_musket_polearm` (declared slot_type melee) now appear in BOTH the ranged and melee slot inventory grids. Player can equip either musket in either slot. Single item per design — equipping in one slot consumes it from the other (vanilla inventory behavior).
- Mechanism: hook `BackendInterfaceItemPlayfab:get_filtered_items`. Vanilla evaluates a filter string ("slot_type == ranged" / "slot_type == melee") against each backend item to populate the slot grid. Hook detects those two filters and APPENDS any cwv musket items the player owns that weren't already in the result. Items keep their declared slot_type in IML — only the UI filter becomes permissive for our muskets.
- Cross-slot equip itself is unhindered — vanilla's `set_loadout_item` doesn't check slot_type compatibility, just stores the ItemId in the slot. The wielded weapon's behavior is determined by its template (musket_template), not by its slot, so muskets fire identically regardless of which slot they're equipped in.

## 0.1.267-dev (2026-05-10) — Musket: belt-and-suspenders spread fix + ammo persistence
- Fixed (attempt 2): polearm musket spread crash. v0.1.266's init-only hook fired (per log: two `patched WeaponSpreadExtension` entries before the crash) but the user STILL crashed. Either a fresh spread extension was created without our init hook firing, OR spread_settings became nil post-init. Added a second `mod:hook("WeaponSpreadExtension", "update")` (full wrapper) that runs BEFORE vanilla's update each frame and patches `spread_settings = SpreadTemplates.handgun` if nil. Belt-and-suspenders — even if init misses, update catches every frame.
- Fixed: ammo refilled to full when the player toggled stance FROM melee TO ranged. Root cause: melee template (musket_template_melee) has no ammo_system extension on its wielded unit, so `total_ammo_fraction()` returned nil during the toggle helper's pre-destroy capture, and we passed nil to `add_equipment` (vanilla treats nil as full ammo). v0.1.267 persists the captured ammo fraction on `item_data.mod_data.cwv_musket_ammo_fraction`. On a melee→ranged toggle where no live ammo can be read, falls back to the persisted value from the previous ranged→melee toggle.

## 0.1.266-dev (2026-05-10) — Polearm musket: enable ranged use + 1P melee Y 1.2 → 1.8
- Re-enabled the v0.1.257 "identical-to-ranged" design for the polearm variant. Template back to `musket_template`, trait back to `ranged_increase_power_level_vs_armour_crit`, stance toggle works again.
- Fixed the v0.1.260 spread-extension crash that previously blocked this design. New `mod:hook_safe("WeaponSpreadExtension", "init")` checks for nil `spread_settings` after vanilla init runs and falls back to `SpreadTemplates.handgun`. Vanilla's name-keyed lookup (`ItemMasterList[item_name]`) returns the BASE spear IML for our cwv variant (no `default_spread_template`), so vanilla sets `spread_settings = nil`. Defensive hook patches it. Only fires when the original lookup returned a template without spread settings — vanilla weapons that have proper settings are unaffected.
- Removed v0.1.260's slot_type gate in toggle helper and exact-match gate in `BackendUtils.get_item_template` hook. Both variants share the same toggle behavior again.
- 1P melee Y scale: `_MELEE_1P_SCALE_FACTOR.Y` `0.8 → 1.2` per user "1.8y" — composes against type-level 1P Y (1.5) for 1.5 × 1.2 = 1.8 in 1P melee. 3P stays at 1.35.

## 0.1.265-dev (2026-05-10) — Inherit-from-variant pass: LONGEST-prefix match
- Fixed: `cwv_es_longsword_shield_*` illusions (the new Saltzpyre greatsword pairings from v0.1.254, plus the original Imperial sword pairings) were rendering at the WRONG scale — too big — because the inherit-from-variant pass at line ~6906 matched `cwv_es_longsword` (the 2H variant) as a prefix BEFORE reaching `cwv_es_longsword_shield`. The 2H variant's transform (`{1.0, 0.8, 0.9}` unified) was applied instead of the shield-specific 3P override (`{0.85, 0.65, 0.75}`).
- Root cause: the loop iterated variants in `_variant_definitions` order and `break`ed on the first prefix match. When `cwv_es_longsword` (shorter prefix) appeared before `cwv_es_longsword_shield` in the list, the shorter one won. Same hazard applies to any variant pair where one item_key is a prefix of another.
- Fix: walk all variants, track the LONGEST item_key that's a prefix of the skin_key, and apply that one's transform. New: any future variant-pair with prefix overlap (longsword family, dual_swords-vs-dual_swords_anything, etc.) gets the right one automatically.

## 0.1.264-dev (2026-05-10) — Musket bayonet: FP/3P camera-mode visibility sync
- Fixed: floating bayonet visible in third-person view (and vice versa) when player switched camera modes. v0.1.249 prune logs confirmed our spawn/wield code was clean (only 2 pairs ever tracked, no orphans, no duplicates) — meaning the "extra" bayonet was actually our LEGITIMATE 1P bayonet still rendering in 3P (and the 3P one in 1P). Vanilla `SimpleInventoryExtension.show_first_person_inventory(show)` and `show_third_person_inventory(show)` toggle the rifle units' visibility per camera, but `World.link_unit` doesn't propagate visibility to children, so the linked bayonet kept rendering regardless.
- Fix: hooks on both `show_first_person_inventory` and `show_third_person_inventory` mirror the called perspective's wielded rifle visibility onto its tracked bayonet via `Unit.set_unit_visibility(bayonet, show)`. Now the 1P bayonet only renders in 1P view; 3P bayonet only in 3P view.

## 0.1.263-dev (2026-05-10) — Tuskgor Javelin: deeper pull-back + suppress 3P offhand spare
- Tuned: stuck-javelin pull-back `_TJ_VISUAL_PULL_BACK_M` `0.30 → 0.60` per user "still too deep". Visual now spawns 60 cm out along the spear's forward axis from the engine-set contact point.
- Fixed: 3P showed two boar spears — the wielded `left_hand_unit` and a second one as the offhand spare via `ammo_unit`. Vanilla `we_javelin` ships an `ammo_unit` pointing at the elf javelin (Kerillian carries spare javelins on her body in 3P), and our skin-registration fallback at line ~4638 sets `ammo_unit = base.ammo_unit and def.left_hand_unit` — so an unset `def.ammo_unit` falls through to the boar spear, doubling it on the body.
- Fix: `def.ammo_unit = "units/weapons/player/wpn_invisible_weapon"` on both `cwv_es_javelin` and `cwv_wh_javelin`. The invisible weapon is a real unit (no crash on `ammo_unit_attachment_node_linking` lookup) but renders nothing — so only the wielded boar spear shows. Affects 1P offhand too. If 1P offhand needs the boar spear back, switch to a hooked GearUtils.create_equipment that hides only the 3P ammo unit instance.

## 0.1.262-dev (2026-05-10) — Bayoneted Musket: revert to melee-only (engine constraint)
- Reverted v0.1.257's "identical-to-ranged" design. Crashed `weapon_spread_extension.lua: spread_settings nil` (GUID 451895b3) for any player whose loadout included the polearm variant. Root cause: `WeaponSpreadExtension.init` does `ItemMasterList[item_name]` to look up the template — for our cwv variant `item_name` is the inherited base name `es_2h_heavy_spear` (per `feedback_cwv_clone_name_clobber.md`), so the lookup returns the BASE spear IML whose template has no `default_spread_template`. Setting `spread_settings = nil`. First update frame crashes on arithmetic against the nil. Our `BackendUtils.get_item_template` hook can't intercept because the call uses a name-keyed lookup with no cwv marker.
- Polearm variant is now melee-only: `template = "musket_template_melee"`, `trait = "melee_attack_speed_on_crit"`. No stance toggle. To fire the musket, player wields the ranged-slot `cwv_es_musket` variant.
- Re-added v0.1.251 gates: `_toggle_musket_stance_and_rewield` short-circuits on `slot_type ~= "ranged"`, and `BackendUtils.get_item_template` only intercepts on exact backend_id `cwv_es_musket_001`.
- The v0.1.259 melee tooltip fields on `musket_template` (max_fatigue_points etc.) stay — harmless when unused, may help future variants.

## 0.1.261-dev (2026-05-10)
- Tuned: `cwv_es_outrider_grenade_launcher` projectile visual swapped from the trollhammer torpedo to the hand grenade mesh per user. The in-flight model now uses `ProjectileUnits.grenade` (`wpn_emp_grenade_01_t1_3p`) instead of `wpn_dr_deus_projectile_01_3ps`. Implemented by cloning the vanilla `Projectiles.dr_deus_01` config to `Projectiles.cwv_outrider_grenade_projectile` and swapping just `projectile_units_template = "grenade"` — all other trollhammer projectile physics (gravity, life_time, impact_type, trajectory) preserved. Then in `_create_outrider_grenade_launcher_template`'s `action_one` walk, each sub-action with `projectile_info == Projectiles.dr_deus_01` is re-pointed at the cloned config. Bardin's native trollhammer is unaffected (we cloned + retargeted; never mutated the source).

## 0.1.260-dev (2026-05-10)
- Tuned: `cwv_es_outrider_grenade_launcher` max_ammo `7 → 10` per user. The cloned `outrider_grenade_launcher_template` inherited `max_ammo = 7` from `dr_deus_01_template_1` (trollhammer base) — no prior override. Added `template.ammo_data.max_ammo = _OUTRIDER_MAX_AMMO` (= 10) inside the existing `if template.ammo_data` block alongside `ammo_hand` and `reload_time`.

## 0.1.259-dev (2026-05-10) — Musket: melee-tooltip fields on ranged template
- Fixed: equipping the polearm musket variant in the melee slot crashed `ui_passes_tooltips.lua:1636: attempt to perform arithmetic on local 'max_fatigue_points'` (GUID 451895b3). The handgun template our `musket_template` clones from has no `max_fatigue_points` (ranged weapons don't have block stamina), but vanilla's tooltip code does arithmetic on that field for ANY equipped weapon — including a ranged-template weapon equipped in a melee slot.
- Fix: add defensive defaults for the melee tooltip fields to `musket_template`: `max_fatigue_points = 8`, `dodge_count = 3`, `block_angle = 180`, `outer_block_angle = 360`, `block_fatigue_point_multiplier = 0.5`, `outer_block_fatigue_point_multiplier = 2`. Values mirror the tuskgor spear template; benign when the weapon is wielded in a ranged slot (the fields just sit unread).

## 0.1.258-dev (2026-05-10) — Tuskgor Javelin: pull stuck visual out of wall
- Tuned: stuck Tuskgor Javelin visual was sitting too deep in surfaces. Added `_TJ_VISUAL_PULL_BACK_M = 0.30` (meters). When `_attach_carrier_visual` spawns the boar spear visual at the parent throwing-axe pup's pose, it now pulls the spawn position back along `Quaternion.forward(rot) * 0.30` so the spear's tip protrudes from the surface instead of disappearing into it. Parent pickup actor stays at the engine-set contact point — only the rendered mesh is offset, so interaction range and outline anchor are unchanged.
- Easy to retune: bump the constant for less depth (more pulled out), reduce towards 0 for deeper sit. If the visual ever floats off the wall after a different change to projectile orientation, this is the first place to check.

## 0.1.257-dev (2026-05-10) — Bayoneted Musket: identical-to-ranged behavior
- Per user "the melee version is melee only — should be identical to the ranged weapon": polearm variant now uses `musket_template` (handgun moveset) by default, same as ranged variant. F triggers stance toggle to `musket_template_melee` and back. The polearm variant differs from the ranged ONLY in slot (melee vs ranged) and visual mesh (Aunty Bessie vs default rifle).
- Reverted v0.1.251 gates: `_toggle_musket_stance_and_rewield` no longer short-circuits on `slot_type ~= "ranged"`, and `BackendUtils.get_item_template` no longer requires exact backend_id `cwv_es_musket_001` — both variants share toggle behavior.
- Trait swapped to `ranged_increase_power_level_vs_armour_crit` (matches ranged variant) since the default mode is now ranged.

## 0.1.256-dev (2026-05-10) — Musket 1P scale Y 1.35 → 1.5
- Added `right_hand_scale_1p = { 0.8, 1.5, 0.8 }` to BOTH `cwv_es_musket` and `cwv_es_musket_polearm` type-transforms — Y bumped from 1.35 to 1.5 (+0.15) on the 1P perspective only. 3P stays at the unified `{ 0.8, 1.35, 0.8 }`. Per `_resolve_field` precedence, the `_1p` field overrides the unified one for 1P units only.

## 0.1.255-dev (2026-05-10) — Bayoneted Musket (melee-slot variant)
- Added: new variant `cwv_es_musket_polearm` ("Bayoneted Musket"). Inherits from `es_2h_heavy_spear` so it occupies the **melee slot** alongside the existing `cwv_es_musket` in the ranged slot — player can wield BOTH at once.
- Visual: `wpn_empire_handgun_t3` (the "Aunty Bessie" rifle mesh) — distinct from the ranged variant's `wpn_empire_handgun_t1`. Both share the type-level scale `{0.8, 1.35, 0.8}` so they read as the same musket family, just held differently.
- Template: uses the existing `musket_template_melee` (clone of Kerillian elf spear). The bayonet child-link, polearm rotation correction, melee position offset, and 1P scale-down all apply automatically since the spawn hook gates on `item_template == musket_template_melee`.
- No stance toggle: the toggle helper now short-circuits when `item_data.slot_type ~= "ranged"`. The polearm variant's action_three still fires the dummy animation but the rewield is skipped — pure melee weapon, no swap to ranged template that wouldn't make sense in a melee slot.
- BackendUtils.get_item_template hook also gates on exact backend_id match (`cwv_es_musket_001`) so the polearm variant's template is never overridden by the stance-swap logic.
- Per-item_type skin pool: `cwv_es_musket_polearm_skins` registered separately from `cwv_es_musket_skins`. Future cosmetic illusions for the polearm can target it independently.

## 0.1.254-dev (2026-05-10) — Imperial Longsword + Shield: add Saltzpyre greatsword meshes
- Added: 7 Saltzpyre greatsword (`wh_2h_sword`) meshes as illusion options on `cwv_es_longsword_shield`. Same wh sword set the 2H `cwv_imperial_longsword` family ships as cross-character illusions per CHANGELOG v0.1.113. All 7 are distinct from the existing Recruit / Nordland / Black Guard mesh family.
- New entries paired with rotating Empire shields by rarity tier:
  - wh skin_01 (`wpn_2h_sword_02_t1`, plentiful) + emp_shield_01_t1
  - wh skin_03 (`wpn_2h_sword_02_t3`, common) + emp_shield_02
  - wh skin_02 (`wpn_2h_sword_02_t2`, rare) + emp_shield_03
  - wh skin_04 (`wpn_2h_sword_04_t2`, exotic) + emp_shield_04
  - wh skin_05 (`wpn_2h_sword_05_t1`, exotic) + emp_shield_05
  - wh skin_02_runed_01 (`wpn_2h_sword_02_t2_runed_01`, unique) + emp_shield_02_runed_01
  - wh skin_05_runed_01 (`wpn_2h_sword_05_t1_runed_01`, unique) + emp_shield_03_runed_01
- Picker now has 15 entries total (8 Imperial + 7 Saltzpyre). Each Empire shield mesh appears 1–2 times paired with different swords.
- Refactor: pairing entries now carry an optional `suffix` field that disambiguates the skin_key when multiple swords pair against the same shield. Without it, the second registration would collide with the first and silently skip. New key format: `cwv_es_longsword_shield_<shield_tail>__<sword_suffix>`. Pre-existing skin keys CHANGE — players who explicitly picked an illusion will need to re-pick. Acceptable in dev iteration.

## 0.1.253-dev (2026-05-10)
- Tuned: `cwv_es_dual_warpriest_hammers` greathammer-illusion grip offsets — split per perspective per user. 1P felt too high at the previous unified value; 3P was fine. Both hands now use `_1p = -0.1` / `_3p = -0.35` (replaces unified right=-0.25, left=-0.3). Effect: in held first-person view the grip pulls back closer to native, while the 3P body view drops the grip 0.35 units down the haft. All 8 illusion entries updated. Both hands at the same offset values now (no more right≠left asymmetry).

## 0.1.252-dev (2026-05-10) — Removed cwv_es_shortsword_shield variant
- Removed: `cwv_es_shortsword_shield` (Shortsword and Shield) variant per user — visual didn't land. The standalone `cwv_es_shortsword` (Sienna dagger moveset on Kruber) is unaffected and stays.
- Code removed: variant def, `shortsword_shield_template` clone + `_create_shortsword_shield_template` (1.20× speed / 0.90× stagger / mace→slashing damage profile swap), `_force_display_unit["cwv_es_shortsword_shield"] = display_shield_sword`, `_seed_targets`/`_item_type_to_skin_table` entries, and the `_register_shortsword_shield_illusions` curated picker (Empire 1h-sword × es_mace_shield rarity-matched pairings).
- Caveat: any existing PlayFab inventory items keyed off `cwv_es_shortsword_shield_001` are now orphaned (auto-registration won't re-create them). Equipping a stale entry would crash. Mitigation if it surfaces: re-add the def temporarily and `wt clear_loadout`, or accept that the user has to swap to a different weapon before next launch.
- **DoD:** Universal walked (forward-ref audit clean — grep'd `shortsword_shield` returns zero hits in the mod source; build hygiene next). Trait gates: N/A (removal). Deferrals: orphan PlayFab cleanup (caveat above).

## 0.1.251-dev (2026-05-10) — Imperial Longsword + Shield: real Empire shields, paired with three sword meshes
- Fixed: `cwv_es_longsword_shield` cosmetic picker showed elf shields among the options. Root cause: the previous `_register_imperial_longsword_shield_illusions` (v0.1.175 → v0.1.250) scanned `ItemMasterList` for entries with `matching_item_key == "es_sword_shield"` — but that pool also contains the auto-generated skin entries for `cwv_we_sword_shield` / `cwv_we_sword_shield_veteran` (Kerillian's elven sword+shield variants), which clone from the same Empire base for template reasons. The leak put `wpn_we_shield_*` meshes into the picker.
- Replaced the IML scan with a HARDCODED pairing table: `_IMPERIAL_LONGSWORD_SHIELD_PAIRINGS` lists 8 Empire shield meshes paired with one of three Imperial Longsword sword meshes (Recruit / Nordland / Black Guard). No IML scan, no elf leak.
- Added 3 sword variations across the 8 illusions (was 1 before):
  - **Recruit Longsword** (`wpn_2h_sword_04_t1`): `wpn_emp_shield_01_t1` (plentiful), `wpn_emp_shield_02` (plentiful)
  - **Nordland Claymore** (`wpn_greatsword`): `wpn_emp_shield_03` (rare), `wpn_emp_shield_03_runed_01` (unique)
  - **Black Guard Blade** (`wpn_2h_sword_03_t2`): `wpn_emp_shield_04` (exotic), `wpn_emp_shield_05` (exotic), `wpn_emp_shield_02_runed_01` (unique), `wpn_emp_shield_04_magic_01` (magic)
- Pairing rationale (best-effort thematic match without localization access): basic state-issue shields → Recruit Longsword (matching basic Reikland regiment kit); mid-tier coastal-style shields → Nordland Claymore (coastal regiment theme); ornate/runed/magic shields → Black Guard Blade (knightly / Knights of Morr theme). Adjustable per shield by editing the pairing table.

## 0.1.250-dev (2026-05-10) — Musket rifle X/Z 0.9 → 0.8 (both 1P and 3P)
- Tuned: `_type_transforms.cwv_es_musket.right_hand_scale` X/Z dropped from 0.9 to 0.8 per user "another 0.1 down on X and Z". Y (barrel length) unchanged at 1.35. Affects BOTH 1P and 3P perspectives since type-level transforms apply to both. The melee 1P additional thin (`{0.8, 0.8, 1.0}`) still composes on top, so 1P melee X = 0.8 * 0.8 = 0.64.

## 0.1.249-dev (2026-05-10) — Musket bayonet: aggressive orphan prune on every spawn
- Added: orphan prune at the START of the `GearUtils.spawn_inventory_unit` hook (before attaching the new bayonet). Walks `_musket_bayonet_pairs`, hides + destroys any bayonet whose rifle is no longer alive, removes the dead-key entry. Catches stale entries from any code path that bypassed our `destroy_wielded` cleanup (world transition, hot-load, equipment re-creation outside `destroy_slot`). Logs `pruned N orphan(s) before new attach` when it cleans up — helps diagnose where the leak comes from. The existing `_wield_slot` orphan cleanup stays as a secondary safety net.

## 0.1.248-dev (2026-05-10) — Tuskgor Javelin: restore tagged-pickup outline
- Fixed: stuck Tuskgor Javelins were losing their white tagged-pickup outline. Since v0.1.190 the carrier-unit pattern hides the parent throwing-axe pup via `Unit.set_unit_visibility(parent, false)`. That flag excludes the parent from every render pass, including the engine's outline pass — so the OutlineExtension on the parent had nothing to draw onto, and the visible boar spear visual (a separate world unit, no OutlineExtension) was never registered with the outline system.
- Fix: maintain a weak-keyed `_carrier_visuals[parent_unit] = visual_unit` map (populated in `_attach_carrier_visual`, cleared in `_detach_carrier_visual`) and hook `OutlineSystem.outline_unit` to mirror every call from a tracked parent onto its visual. The visual unit gets the same `flag` / `channel` / `do_outline` / `apply_method` / `outline_settings` arguments, so all outline channels (tag, ping, threat) propagate identically. The original parent call still runs (cheap no-op since the parent is invisible — keeps the engine's internal accounting consistent).
- Pattern is general: any future variant using the carrier-visual hide-parent trick gets outline forwarding for free as long as it populates `_carrier_visuals`.

## 0.1.247-dev (2026-05-09) — Musket melee Y offset 0.05→0.06, 1P thinner X/Y
- Tuned: melee Y grip offset `0.05 → 0.06`. Full vector now `{ 0, 0.06, -0.3 }`.
- Switched 1P melee scale-down from uniform `0.85` to per-axis factors `{ 0.8, 0.8, 1.0 }` per user "0.8x and 0.8y" (Z unchanged). Renamed constant `_MELEE_1P_SCALE_DOWN` → `_MELEE_1P_SCALE_FACTOR`.

## 0.1.246-dev (2026-05-09) — Musket melee Y offset 0 → 0.05

## 0.1.245-dev (2026-05-09) — Musket melee grip offset Y=0, Z restored
- Restored Z=-0.3 (per v0.1.230) — v0.1.244 zeroed all three by misinterpretation. Now `_MELEE_LOCAL_OFFSET = { 0, 0, -0.3 }`: no Y offset (per "no offset again"), Z grip-height drop preserved.

## 0.1.244-dev (2026-05-09) — Musket melee grip offset zeroed
- Zeroed `_MELEE_LOCAL_OFFSET` to `{ 0, 0, 0 }` per user "let's try no offset again". Vanilla polearm `attachment_node_linking` offset alone now positions the rifle.

## 0.1.243-dev (2026-05-09) — Musket melee range_mod 1.35 → 1.2
- Tuned: every melee sub-action's `range_mod` overridden to 1.2 (vanilla tuskgor uses 1.35). Bayonet now reaches less than a full polearm haft. `range_mod_add` (the per-sub-action additive component, 0.25-1.0) kept vanilla.

## 0.1.242-dev (2026-05-09) — Musket melee Y grip offset 0.1 → -0.08

## 0.1.241-dev (2026-05-09) — Musket melee: outermost Z π → 3π/2
- Tuned: outermost Z rotation bumped from π to 3π/2 (adds another 90°). Total melee rotation: `q_z2(3π/2) * q_y(-π/2) * q_z(π/2) * q_x(π)`.

## 0.1.240-dev (2026-05-09) — Musket bayonet Y 0.76 → 0.8

## 0.1.239-dev (2026-05-09) — Musket bayonet diagnostic logging
- Added: log lines in `_attach_musket_bayonets` (counts pairs after each attach, flags skips) and in `_sync_all_bayonets_visibility` (counts orphans destroyed + shown + hidden). Helps diagnose user-reported "floating bayonet on both melee and ranged" — the existing idempotent attach + orphan cleanup defenses should prevent this, but if it's still happening the logs will show whether attach is firing twice, which rifle the orphan is bound to, etc.

## 0.1.238-dev (2026-05-09) — Musket melee: add outermost Z=π
- Per user "needs to be rotated 180 about z" after v0.1.235 fixed direction. Added `q_z2 = π` at outermost composition position. Total: `q_z2(π) * q_y(-π/2) * q_z(π/2) * q_x(π)`.

## 0.1.237-dev (2026-05-09)
- Tuned: `cwv_es_maul` X/Y `1.075 → 1.0` per user (drop the 7.5% width bump, native X/Y). Scale now `{1.0, 1.0, 1.6}` — pure Z lengthening, no width thickening. Z still 60% longer than native.

## 0.1.236-dev (2026-05-09)
- Tuned: `cwv_es_maul` grip offset `{0, 0, 0.35} → {0, 0, 0.2}` per user. Z still positive (lowers grip on this family), but reduced — hand sits less far down the haft.

## 0.1.235-dev (2026-05-09) — Musket melee: add X=π
- Per user "off by 180 on the X axis", add `q_x = π` on top of v0.1.234's composition. Total: `q_y(-π/2) * q_z(π/2) * q_x(π)`.

## 0.1.234-dev (2026-05-09) — Musket melee: flip Y sign
- Reverted v0.1.233's Z=π. Adding rotations on every axis hasn't worked. Trying a sign flip on the existing Y instead: `+π/2 → -π/2`. Total composition: `q_y(-π/2) * q_z(π/2)`.

## 0.1.233-dev (2026-05-09) — Musket melee: revert X, try Z=π
- Reverted v0.1.232's -X attempt (X axis attempts in both directions have been wrong). Bumping Z from π/2 to π instead. Total composition: `q_y(π/2) * q_z(π)`.

## 0.1.232-dev (2026-05-09) — Musket melee: revert Y, try -X
- Reverted v0.1.231's Y bump (π → back to π/2). User reports Y was the wrong axis. Added `q_x = -π/2` instead — opposite direction from v0.1.225's +π/2 X attempt that was also wrong. Total composition: `q_y(π/2) * q_z(π/2) * q_x(-π/2)`. If still wrong, next iterations: flip sign of any of the three, or try removing one axis.

## 0.1.231-dev (2026-05-09) — Musket melee Y rotation π/2 → π
- Tuned: melee Y-axis rotation bumped from `π/2` (90°) to `π` (180°) per user "rifle is upside down — add another 90° CCW about Y". The composed rotation is now `q_y(π) * q_z(π/2)`. Z component unchanged.

## 0.1.230-dev (2026-05-09) — Musket melee grip offset
- Added: `_MELEE_LOCAL_OFFSET = { 0, 0.1, -0.3 }` translation delta applied to BOTH 1P and 3P rifle units in melee mode. Reads current local position (set by vanilla's polearm `attachment_node_linking`), adds the delta, sets back — compose-friendly so it doesn't fight the attachment offset. Y +0.1 pushes slightly forward along the barrel; Z -0.3 drops the grip height. Applied alongside the existing Y+Z 90° rotation correction.

## 0.1.229-dev (2026-05-09)
- Tuned: `cwv_es_maul` Z scale `1.4 → 1.6` per user — longer haft (60% longer than native, was 40%).
- Tuned: greathammer-on-1H-hammer illusions across `cwv_es_warpriest_hammer`, `cwv_es_warpriest_hammer_shield`, and `cwv_es_dual_warpriest_hammers` — Z grip offsets HALVED per user (grip was too high on the rescaled mesh):
  - Skullsplitter (1H) right offset `-0.55 → -0.275` (8 entries)
  - Shield variant right offset `-0.55 → -0.275` (8 entries)
  - Dual variant right offset `-0.5 → -0.25`, left offset `-0.6 → -0.3` (8 entries each)
- Tuned: greathammer-on-1H-hammer illusion scales BUMPED +0.1 on every axis per user — `{0.75, 0.75, 0.575}` → `{0.85, 0.85, 0.675}`. Applied to all 32 hand-scale fields (24 right + 8 left) across all three variants. Negative offsets on the dual variant remain asymmetric (right=-0.25, left=-0.3) as before.

## 0.1.228-dev (2026-05-09) — Musket bayonet: idempotent attach + orphan cleanup
- Fixed: extra floating bayonet on ranged equip (user report). Two defensive fixes:
  - `_attach_musket_bayonets` now skips per-rifle if a bayonet is already tracked for it. Without this, any code path that re-fires our `GearUtils.spawn_inventory_unit` hook on the same rifle (e.g. cosmetic application that refreshes equipment without going through `destroy_wielded`) would attach a SECOND bayonet, leaving the first as an orphan tracked-but-not-cleaned unit.
  - `_sync_all_bayonets_visibility` (runs after every `_wield_slot`) now opportunistically destroys orphan bayonets (rifle dead but bayonet alive). Cleans up after any code path that bypasses `destroy_wielded`.

## 0.1.227-dev (2026-05-09) — Musket melee back to tuskgor spear (vanilla stats) + 1P scale-down
- Reverted: melee template clones `Weapons.two_handed_heavy_spears_template` (Kruber's tuskgor spear) again per user "elf spear animations don't match up nicely". Force-load swap: `state_machines/melee/spear` → `state_machines/melee/polearm`. Both spear templates use `AttachmentNodeLinking.polearm` so the existing rotation correction (Y+Z 90°) still applies.
- Removed: damage and speed scaling per user "make it have its normal speed and melee values". The `_scale_melee_damage_profile` clone-and-multiply is no longer called; vanilla tuskgor spear stats kept verbatim. (Helper function and constants left in source for easy re-enabling if desired.)
- Added: 1P-only scale-down for the rifle when in melee mode. Reads the existing local scale (set by the `GearUtils.create_equipment` hook from the type-level transform `{0.9, 1.35, 0.9}`) and multiplies by `_MELEE_1P_SCALE_DOWN = 0.85`. 3P unit kept at the original scale so other players see the full-size musket-bayonet. Tunable via the constant.

## 0.1.226-dev (2026-05-09) — Musket melee rotation: swap X for Z axis
- Reverted v0.1.225's +90° X rotation per user "wrong axis was rotated". Now composing +90° Y + +90° Z. Z is the third orthogonal local axis; if direction is reversed, flip the Z sign to -90°.

## 0.1.225-dev (2026-05-09) — Musket melee rotation += +90° X, bayonet position
- Added: second rotation axis on the rifle in melee mode. v0.1.220's single +90° Y (barrel axis) wasn't enough — the rifle was still held at a wrong pitch in the spear-grip pose. Now composes `q = q_y * q_x` where both quaternions are +90° axis-angle rotations (Y barrel + X pitch up). Order: X applied first in local frame, then Y on top. If the resulting pose still reads wrong, easy to flip order to `q_x * q_y` or flip signs.
- Bayonet position: `{0, 0.72, 0.05}` → `{0, 0.76, 0.025}` per user direction. Y +0.04 (closer to muzzle), Z -0.025 (slightly lower).

## 0.1.224-dev (2026-05-09) — Musket: drop bad display_unit force-load, override on melee template
- Fixed: "Resource not found" crash at mod load (GUID 52f91814). v0.1.220 force-loaded `units/weapons/weapon_display/display_2h_spears_wood_elf` via `Managers.package:load`, but that path is NOT in `scripts/network_lookup/inventory_package_list.lua` — it's bundled inside another package, not a loadable per-asset path. Stingray returned a hard "Resource not found" because no synthetic per-asset package exists at that path.
- Removed: the `display_2h_spears_wood_elf` force-load. Only the elf spear's state machine is force-loaded now (verified present at `inventory_package_list.lua:280`).
- Added: explicit `template.display_unit = "units/weapons/weapon_display/display_1h_handguns"` override on `musket_template_melee` so the inventory previewer doesn't try to spawn the unloadable spear display unit when the cosmetics menu opens for the musket in melee mode. The handgun's display rig is already loaded for Kruber and visually serves the same purpose (spins the rifle mesh on a stage).

## 0.1.223-dev (2026-05-09) — Musket bayonet scale tweak
- Tuned: `_MUSKET_BAYONET_SCALE` from `{0.25, 0.7, 0.25}` to `{0.35, 0.6, 0.2}`. X bumped (slightly thicker side profile), Y dropped (shorter blade), Z dropped (thinner cross-section).

## 0.1.222-dev (2026-05-09) — Musket cosmetic illusions (Aunty Bessie + Single-Shooter)
- Added: two cosmetic illusion options for `cwv_es_musket`:
  - **Aunty Bessie** — `wpn_empire_handgun_t3` (cloned from vanilla `es_handgun_skin_05`)
  - **Von Meinkopt's Single-Shooter** — `wpn_empire_handgun_t2` (cloned from vanilla `es_handgun_skin_04`)
- New `_register_musket_handgun_illusions()` registers both as `weapon_skin` IML entries with `matching_item_key = "cwv_es_musket"`, mirrors them into `WeaponSkins.skins`, appends to the variant's exotic-tier `cwv_es_musket_skins` combo table, and injects keys into `NetworkLookup.weapon_skins` + `item_names`. Display names registered via `_display_names[<key>_name] = "..."` so the inventory shows the human-readable label instead of the variant's generic name.
- Force-load `wpn_empire_handgun_t2/_t3` (1P + 3P) at mod init via `Managers.package:load` — Kruber's es_handgun loadout only auto-loads the t1 mesh, so applying these illusions without pre-load would crash "Resource not loaded" (same Tuskgor pattern).
- Both illusions inherit the type-level scale `{0.9, 1.35, 0.9}` (musket stretch + thinning), keep all musket stat changes (doubled damage, 2x reload, 12 ammo, 25m alert), and the bayonet child-link still attaches since the spawn-hook gate is on `item_template == Weapons.musket_template`.

## 0.1.221-dev (2026-05-09) — Musket stance toggle: ammo persistence + floating bayonet fix
- Fixed: every stance toggle was a free reload. The destroy_slot + add_equipment cycle spawned the new weapon at full ammo, ignoring the ammo count the player had at toggle time. Now `_toggle_musket_stance_and_rewield` reads the rifle's `ammo_system` extension and calls `:total_ammo_fraction()` BEFORE `destroy_slot`, then passes the fraction as the 5th arg to `add_equipment(slot, item_data, nil, nil, ammo_fraction)`. The new weapon spawns with the same proportional ammo.
- Fixed: floating bayonet visible for one frame after stance toggle. `Managers.state.unit_spawner:mark_for_deletion(bayonet)` is async — it queues the unit for end-of-next-frame destruction. While queued the bayonet still rendered at its last world position (frozen where the rifle was when destroyed). New behavior: `_detach_musket_bayonet` calls `Unit.set_unit_visibility(bayonet, false)` BEFORE marking for deletion, so the bayonet is invisible for the frame between mark and destroy.

## 0.1.220-dev (2026-05-09) — Musket melee = elf spear + 90° Y rotation in melee mode
- Reverted: `musket_template_melee` clones `Weapons.two_handed_spears_elf_template_1` (Kerillian's elf spear) again per user direction, instead of v0.1.207's Kruber-native heavy spear. The elf spear is the originally-intended moveset.
- Force-load: pre-load the elf spear's state machine (`units/beings/player/first_person_base/state_machines/melee/spear`) AND display unit (`units/weapons/weapon_display/display_2h_spears_wood_elf`) at mod init via `Managers.package:load`. Without this, Kruber crashes "Resource not loaded" on stance toggle because Kerillian's package isn't in his memory. Same Tuskgor-pup pattern.
- Added: 90° rotation about the rifle's local +Y axis (barrel axis) when in melee mode. The elf spear's polearm `attachment_node_linking` holds the rifle perpendicular to its intended orientation; the spawn-hook applies `Unit.set_local_rotation(rifle, 0, Quaternion.axis_angle(Vector3(0,1,0), π/2))` after vanilla mounts the rifle, spinning the receiver/stock to face the right way. Counter-clockwise per user direction; if visually wrong, flip the sign to `-π/2`.

## 0.1.219-dev (2026-05-09) — Musket bayonet Y 0.8 → 0.72, Z 0 → 0.05
- Tuned: `_MUSKET_BAYONET_LOCAL_TRANSLATION` Y from 0.8 to 0.72 (closer to muzzle) and Z from 0 to 0.05 (small upward bump from barrel level) per user direction.

## 0.1.218-dev (2026-05-09) — Musket bayonet Y offset 0.9 → 0.8
- Tuned: `_MUSKET_BAYONET_LOCAL_TRANSLATION` Y from 0.9 to 0.8 per user direction. Bayonet sits slightly closer to the muzzle.

## 0.1.217-dev (2026-05-09) — Musket bayonet model fix (Soldier's Longsword)
- Fixed: bayonet model was using `wpn_emp_sword_04_t1`, which is actually the FALCHION mesh (matching_item_key = "wh_1h_falchion" in `item_master_list_weapon_skins.lua:5185`), not a Kruber 1H sword. v0.1.211's "use the 2nd 1h sword model" interpretation picked it because of numerical proximity — wrong path.
- Switched to `wpn_emp_sword_03_t1` — the "Soldier's Longsword" cosmetic skin for `es_1h_sword` (verified via `cosmetics_tweaker/VETERAN_SKIN_CATALOG.md:900`). Both 1P and 3P unit paths updated, with corresponding force-load constants pointing at the new mesh.

## 0.1.216-dev (2026-05-09)
- Tuned: `cwv_es_poleaxe` scale X/Y `0.75 → 0.9` per user (v0.1.215's 0.75 was a bit too thin). Now `{0.9, 0.9, 0.65}` — light X/Y thinning, Z still 35% shorter than native.

## 0.1.215-dev (2026-05-09)
- Tuned: `cwv_es_poleaxe` scale `{1.0, 1.0, 0.65}` → `{0.75, 0.75, 0.65}` per user. Halberd mesh was reading too elongated on the Y axis at native 1.0 — now thinned 25% on both X and Y to match each other while Z (length) stays at 0.65. Type-level so default + every `es_halberd_skin_*` illusion in `cwv_es_poleaxe_skins` inherits.

## 0.1.214-dev (2026-05-09)
- Tuned: rescaled-greathammer illusions on `cwv_es_warpriest_hammer` (1H Skullsplitter) and `cwv_es_warpriest_hammer_shield` (Skullsplitter + shield) — Z grip offset `-0.5 → -0.55` per user (grip a bit too high; pulled hand 0.05 further down the haft). All 16 entries (8 + 8) updated. Negative Z lowers grip on this rescaled-greathammer mesh family (per-model authoring axis flipped from the general +Z = lower convention). Surgical replace targeted the `right_hand_offset = ..., can_wield` pattern, which excludes the 8 dual-warpriest-hammers entries (those have `left_hand_offset` between the offset and `can_wield`). Dual variant grip unchanged at right=-0.5, left=-0.6 (asymmetric per earlier).

## 0.1.213-dev (2026-05-09)
- Tuned: `cwv_es_maul` grip offset Z `0.5 → 0.35` per user. v0.1.176's value pulled the hand too far toward the bottom of the haft; this is a more moderate drop. +Z still lowers grip on this model family per `feedback_grip_offset_sign.md`.

## 0.1.212-dev (2026-05-09)
- Tuned: `cwv_es_rapier` scale `{1.0, 1.75, 1.0}` → `{1.05, 1.15, 1.0}` per user. v0.1.196's max-Y broadsword silhouette read as exaggerated; restoring a lighter touch — small X bump for slight side-profile thickening, modest Y bump for cup-guard depth, Z native.

## 0.1.211-dev (2026-05-09) — Musket polearm SM force-load + bayonet swap
- Fixed: `Resource not loaded` crash on weapon special key (GUID 46e89cd8). v0.1.207's `musket_template_melee` clones Kruber's NATIVE heavy-spear template, but its state machine `units/beings/player/first_person_base/state_machines/melee/polearm` is only loaded for Kruber when his current loadout includes `es_2h_heavy_spear`. If no career has the heavy spear equipped, the polearm SM isn't in memory and the stance toggle's wield path crashes when it tries to spawn a weapon with that SM.
- Fix: force-load the polearm state machine at mod init via `Managers.package:load(_MUSKET_MELEE_STATE_MACHINE, "cwv_musket_melee_sm", nil, true, true)` — same Tuskgor-pup pattern. Stingray treats per-asset paths as synthetic packages.
- Bayonet model swap: `wpn_emp_sword_02_t1` → `wpn_emp_sword_04_t1` (1P + 3P) per user "use the 2nd 1h sword model". `sword_04_t1` is the next distinct 1H sword mesh in vanilla's Empire sword catalog (`sword_02_t2` is just a t2 reskin of the same model, `sword_03` is magic-only). Force-load constants updated to point at the new mesh paths.
- Bayonet position: `{0, 1.0, 0}` → `{0, 0.9, 0}` per user spec ("at 0.9y"). Slightly closer to the muzzle (0.9 instead of 1.0 along the rifle's barrel-forward Y axis).

## 0.1.210-dev (2026-05-09)
- Tuned: `cwv_es_longsword_shield` split right-hand scale per perspective. v0.1.206's unified `{0.85, 0.65, 0.75}` made the 3P silhouette read right next to a shield but the 1P held view came out too small. Now 1P uses `{1.0, 0.8, 0.9}` (back to the 2H Imperial Longsword family scale, which is what the held view was tuned to before the shrink), and 3P keeps `{0.85, 0.65, 0.75}`. Grip offset stays unified at `{0, 0, -0.065}` (works for both perspectives). Pattern: `right_hand_scale_1p` / `right_hand_scale_3p` override the unified field per `_resolve_field`. Same approach used by `cwv_es_dual_swords`'s 1P-only +10% bump.

## 0.1.209-dev (2026-05-09)
- Tuned: rescaled greathammer illusions on `cwv_es_warpriest_hammer` — Z grip offset `-0.6 → -0.5` per user. Hand was sitting too high on the haft (toward the head); pulled grip back down 0.1 units. All 8 entries (`cwv_es_warpriest_hammer_2h_hammer_01/02/03/04/04_runed_01/04_runed_02/06/06_runed_01`) updated. Scale unchanged at `{0.75, 0.75, 0.575}`.

## 0.1.208-dev (2026-05-09) — Musket bayonet visibility sync
- Fixed: bayonet stayed visible when the rifle was unwielded (player swapped to a different weapon — bayonet floated alone in space). VT2's wield system hides the rifle's units via `Unit.set_unit_visibility(rifle, false)` instead of destroying them, and Stingray's `World.link_unit` only propagates transforms to child units, NOT visibility. So the bayonet kept rendering with full opacity while its parent rifle was hidden.
- Fix: track all spawned bayonet pairs in a weak-keyed `_musket_bayonet_pairs[rifle] = bayonet` table. New `mod:hook_safe("SimpleInventoryExtension", "_wield_slot")` runs after every weapon swap, walks the table, and sets each bayonet's `Unit.set_unit_visibility(bayonet, should_show)` based on whether its rifle is the currently-wielded weapon (`equipment.right_hand_wielded_unit` / `_3p`). When the player wields the musket → bayonet shows. When they swap to another slot → bayonet hides.
- The existing `GearUtils.destroy_wielded` cleanup hook also clears the tracking entry so we don't try to read visibility off a dead key.

## 0.1.207-dev (2026-05-09) — Musket melee template switch + bayonet axis fix
- Fixed: `Resource not loaded` crash on weapon special (GUID 1363574c). v0.1.205's `musket_template_melee` cloned `Weapons.two_handed_spears_elf_template_1` (Kerillian's elf spear), which references state_machine `units/beings/player/first_person_base/state_machines/melee/spear` and display_unit `display_2h_spears_wood_elf` — both live in Kerillian's package and aren't loaded for Kruber. Switched to `Weapons.two_handed_heavy_spears_template` (Kruber's NATIVE tuskgor spear), which uses `units/beings/player/first_person_base/state_machines/melee/polearm` and other Kruber-loaded resources. No cross-character package issue.
- Damage tuning preserved (attack ×0.85, stagger ×1.5, anim_time ×0.85). Functionally a polearm thrust moveset like the elf spear; visually plays Kruber's heavy-spear animations on the rifle. If we want elf-spear flavor specifically later, it'd require force-loading the elf spear's package via `Managers.package` per the cross-character pattern.
- Bayonet position: `{0, -0.2, 1.0}` → `{0, 1.0, 0}`. Re-deduced axis convention from the user's prior "elongate the rifle on the Y axis" — rifle's local +Y IS the barrel direction (which is why scaling Y stretches it lengthwise). v0.1.205's Z=1.0 pushed the bayonet 1m along the perpendicular "up" axis (hence "still floating up high"). v0.1.207 puts it 1m along +Y (toward the muzzle) with zero Z offset (no vertical shift).
- Action_three on melee template no longer specifies an `anim_event` — vanilla state machines fall through cleanly when omitted (current pose holds for total_time). Was attempting `to_unwield` which the polearm SM doesn't author cleanly.

## 0.1.206-dev (2026-05-09)
- Tuned: `cwv_es_longsword_shield` right-hand sword scale `{1.0, 0.8, 0.9}` → `{0.85, 0.65, 0.75}` (−0.15 on every axis) per user direction. The 2H Imperial Longsword family's mesh felt too big when paired with a shield; the shrunk-down version reads better as a one-handed longsword. Left hand (the shield) untouched; grip offset `{0, 0, -0.065}` preserved.

## 0.1.205-dev (2026-05-09) — Musket runtime template swap + bayonet position tweak
- Replaced the v0.1.203-204 dual-sub-action stance toggle (which crashed `action_sweep.lua: bad argument #4 to 'immediate_raycast'`, GUID e0c52d77, because the musket sweep sub-action lacked `dedicated_target_range` and other sweep-required fields the action-sweep code path expected) with a true runtime template swap, per user direction.
- New: `Weapons.musket_template_melee` — full clone of `Weapons.two_handed_spears_elf_template_1` (Kerillian's spear). Damage tuning per user spec ("slow it down + add stagger"): every sub-action's damage_profile is cloned with attack ×0.85, impact (stagger) ×1.5, and `anim_time_scale` ×0.85 (15% slower swings). The cloned profiles are registered in `NetworkLookup.damage_profiles` so MP hit RPCs serialize correctly.
- New stance toggle mechanism: F (action_three) on either template runs `_toggle_musket_stance_and_rewield(player_unit)` which:
  1. Reads `item_data.mod_data.cwv_musket_stance` (per-item flag, persists across wield/unwield)
  2. Flips the flag (`ranged ↔ melee`)
  3. Calls `inventory_extension:destroy_slot(slot, true)` then `add_equipment(slot, item_data)` then `wield(slot)` — full unequip+equip cycle
- New hook `BackendUtils.get_item_template`: when the cycle re-creates the slot, this hook reads the (now-flipped) stance flag and returns `Weapons.musket_template_melee` instead of `musket_template`. The recreated weapon spawns with the correct moveset.
- Bayonet child-link hook now fires for BOTH `Weapons.musket_template` and `Weapons.musket_template_melee` (was: only `musket_template`), so the bayonet stays attached when the player toggles stance.
- Bayonet position tweak: from `{0, 0, 0.55}` to `{0, -0.2, 1.0}` — push further forward along the barrel (Z 0.55 → 1.0) and add downward shift (Y 0 → -0.2) to bring it from "floating above" to muzzle level. Tunable via `_MUSKET_BAYONET_LOCAL_TRANSLATION` constant — iterate as needed. Rotation unchanged (user confirmed correct in v0.1.204).
- The `lookup_data` attach (v0.1.204 fix) is preserved on both templates so neither crashes on first chain-resolve.
- ANIMATION CAVEAT: musket_template_melee uses Kerillian's spear's state_machine, which means in melee stance the player holds the rifle in a 2H polearm grip and swings spear-style animations. Visually plausible for a musket-bayonet drilling stance, but not a perfect rifle-pose-with-thrust. Iteration territory.

## 0.1.204-dev (2026-05-09) — Musket crash fix + bayonet rotation + RMB aim restore
- Fixed: crash on first chain resolve through any musket sub-action — `action_utils.lua: attempt to index field 'lookup_data' (a nil value)` (crash GUID ec072975). Vanilla `weapons.lua:305-312` attaches `lookup_data` to every sub-action when `Weapons[<key>]` is initialized at boot. Sub-actions added at mod load time miss this pass. Now we manually attach `lookup_data = { item_template_name, action_name, sub_action_name }` to every entry on the musket template after all our additions/clones land — idempotent so vanilla sub-actions are safely re-set.
- Fixed: right-click no longer fires the gun. v0.1.203's `_augment_chain` was called on `action_two.default` and stripped the vanilla `{action="action_one", sub_action="zoomed_shot"}` chain entry, leaving only our prepended dual `default` entries — so RMB→aim→LMB became RMB→aim→regular shot, plus the strip-and-prepend reordering broke the chain selector. v0.1.204 leaves action_two's chain untouched (vanilla zoom and zoomed_shot intact). The `_augment_chain` strategy switched from "strip-and-prepend" to "just prepend" everywhere — original entries are preserved and only act as fallbacks if our dual entries fail their conditions.
- Fixed: bayonet now points along the rifle's barrel instead of perpendicular. Two corrections:
  - **Position**: `_MUSKET_BAYONET_LOCAL_TRANSLATION` from `{0, 0.55, 0}` (Y-forward) to `{0, 0, 0.55}` (Z-forward). The rifle's barrel-forward is its local +Z, not +Y as v0.1.200 assumed.
  - **Rotation**: new `_MUSKET_BAYONET_LOCAL_ROTATION_AXIS = {1, 0, 0}` and `_ANGLE = -π/2`. The 1H sword model's blade extends along its local +Y; rotating -90° about X swings the blade to point along world Z (the rifle's barrel direction). Without this rotation the bayonet's blade was perpendicular to the rifle (sticking out the side).
  - Both constants are still tunable for fine-grained position/rotation/scale adjustments.

## 0.1.203-dev (2026-05-09) — Musket bayonet visibility fix + true stance toggle + thinner rifle
- Fixed: bayonet wasn't appearing in-game. The `GearUtils.spawn_inventory_unit` hook was checking `item_data.name == "cwv_es_musket"`, but per `feedback_cwv_clone_name_clobber.md` cwv variants inherit the BASE weapon's name (so `item_data.name` was always `"es_handgun"`). Switched to `item_template == Weapons.musket_template` (reference-identity comparison on the template table) — bulletproof and doesn't depend on string fields that get clobbered.
- Changed: rifle scale from `{ 1.0, 1.35, 1.0 }` to `{ 0.9, 1.35, 0.9 }`. X and Z (barrel cross-section / stock width) thinned by 10% so the musket reads as long-and-slender, not just stretched. Y stretch unchanged.
- Replaced single-press bayonet thrust (v0.1.202) with a true stance toggle:
  - F (action_three) toggles between `"ranged"` and `"melee"` stance, stored on the wielded musket unit's data via `Unit.set_data(rifle, "cwv_musket_stance", ...)`. Default stance is ranged on each fresh wield.
  - In ranged stance: LMB fires the rifle (vanilla `action_one.default`), right-click zooms (vanilla `action_two`).
  - In melee stance: LMB swings the bayonet (`action_one.default_melee`, `kind = "sweep"` with the slowed/stagger-boosted `cwv_musket_bayonet_thrust` damage profile), right-click does nothing (zoom disabled).
  - F (action_three) is a `kind = "dummy"` no-damage action that just plays a brief `reload` anim and runs the toggle in `enter_function`.
- Mechanism: every chain entry that targets `action_one` is duplicated into TWO parallel entries — one with `sub_action = "default"` (gated by `chain_condition_func` returning true in ranged stance) and one with `sub_action = "default_melee"` (gated on melee). The chain selector iterates entries in order and picks the first whose chain_condition passes, so the right sub-action fires for the current stance. Parallel pairs are wired into action_one.default, action_one.zoomed_shot, action_one.default_melee, action_two.default, action_three.default, plus cloned wield/reload action chains. Wield + reload are CLONED off the global `ActionTemplates.wield` / `.reload` (which have empty allowed_chain_actions and are shared by every weapon — modifying them in place would affect Bardin's handgun etc).
- ANIMATION CAVEAT: handgun state machine doesn't author melee swing events. Bayonet uses `anim_event = "reload"` as a stand-in (forward arm motion). Damage delivery is independent of animation, so the actual hit register works correctly even if the visual is awkward.

## 0.1.202-dev (2026-05-09) — Musket bayonet thrust on special key
- Added: `cwv_es_musket` action_three (special key F) is now a single-press bayonet melee thrust. Uses `cwv_musket_bayonet_thrust` damage profile (clone of Kerillian spear's `heavy_slashing_smiter_stab_polearm` with attack × 0.85 and impact × 1.5 — slowed per-thrust damage but heavier stagger, per the user "use it like his 1h spear, slow down + add stagger" spec).
- Wiring: action_three subaction added to musket template; `_add_bayonet_chain_to` helper appends an `{action_three, input=action_three}` chain entry to `action_one.default`, `action_one.zoomed_shot`, and `action_two.default` allowed_chain_actions so F is reachable from any handgun state.
- Damage profile: `kind = "sweep"` runs a melee damage-window collision (window 0.15-0.45 of total_time 1.4s), `range_mod = 1.5` for long bayonet reach, hit_effect/sounds taken from spear stab (`stab_hit`, `stab_hit_armour`).
- Animation note: handgun state machine doesn't author melee swing events, so `anim_event = "reload"` is used as a stand-in (forward arm motion that vaguely reads as a thrust). The actual damage delivery is independent of animation. Visual fidelity is the v3 pursuit — full template-swap stance toggle would require runtime mechanism vanilla doesn't natively support.
- NetworkLookup: bayonet damage profile registered in `NetworkLookup.damage_profiles` (mirrors the v0.1.201 fix for the ranged shot profile).

## 0.1.201-dev (2026-05-09) — Musket NetworkLookup fix
- Fixed: firing the musket crashed with `[NetworkLookup.lua] Table damage_profiles does not contain key: cwv_musket_shot` (crash GUID a8094388). The cloned damage profile was registered into `DamageProfileTemplates` but not into `NetworkLookup.damage_profiles`, so the hit-event RPC serialization couldn't resolve it. Added the same `rawset(tbl, idx, key) / rawset(tbl, key, idx)` injection used by `_clone_damage_profile` in `_create_cwv_musket_damage_profile`.

## 0.1.200-dev (2026-05-09) — Musket variant (cwv_es_musket)
- Added: new Kruber ranged variant `cwv_es_musket` ("Musket"). Available to all four Kruber careers as an exotic-rarity item alongside the vanilla rifle.
- Visual: vanilla rifle mesh (`wpn_empire_handgun_t1`) stretched 1.35x along Y (length axis) via type-level `_type_transforms.cwv_es_musket.right_hand_scale = { 1.0, 1.35, 1.0 }`. Long-musket silhouette without changing barrel thickness.
- Bayonet: a thinned-and-shortened copy of Kruber's 1H sword (`wpn_emp_sword_02_t1`) is spawned and `World.link_unit`'d to the rifle unit at equip time (one for 1P, one for 3P). Tracking via `Unit.set_data(rifle, "cwv_musket_bayonet", ...)`; cleanup hook on `GearUtils.destroy_wielded` destroys the bayonet when the rifle is destroyed (weapon swap, level end). Bayonet position/scale tunable via `_MUSKET_BAYONET_LOCAL_TRANSLATION = { 0, 0.55, 0 }` and `_MUSKET_BAYONET_SCALE = { 0.25, 0.7, 0.25 }` constants.
- Damage: `cwv_musket_shot` damage profile — clone of Kruber's handgun's `shot_sniper` with `power_distribution_{near,far}.attack` and `.impact` both 2x on default_target and per-target overrides. Dropoff curve, shield_break flag, and armor modifiers all preserved (close-range hits land hardest, far-range still penetrates armor but at reduced damage).
- Reload: `ammo_data.reload_time = 3.0` (vanilla 1.5).
- Ammo: `ammo_data.max_ammo = 12` (vanilla 16). `ammo_per_clip` and `ammo_per_reload` stay at vanilla 1 — bolt-action rhythm, one shot per chamber.
- Loudness: `alert_sound_range_fire = 25` on every firing sub-action (vanilla 10) — matches blunderbuss's audible radius. Black-powder boom broadcasts the wielder's position to a much wider area than the standard rifle.
- Cross-character package: bayonet sword units (1P + 3P) force-loaded at mod init via `Managers.package:load`, mirroring the Tuskgor Javelin pup pattern (per `feedback_cwv_cross_character_unit_packages.md`). The rifle's package auto-loads via inventory; the sword unit doesn't, so without this the bayonet spawn would assert `Unit not found`.
- TODO(v2): bayonet melee mode bound to the special key. Plan: clone Kerillian's spear moveset (`two_handed_spears_elf_template_1`) and swap the entire weapon template at runtime when the player presses F. Substantial new infrastructure (template-swap state machine; vanilla doesn't natively support stance-toggling weapons), so deferred until v1 ships and stabilizes.

## 0.1.198-dev (2026-05-09)
- Fixed: grip on the scaled-down greathammer cosmetic illusions (es_2h_hammer_skin_*) was sitting too low on the haft for all three Warrior-Priest hammer variants. Bumped `right_hand_offset` Z from `-0.04` to `-0.6` (and matching `left_hand_offset` on the dual variant) on every greathammer illusion entry — 8 single, 8 dual (16 hands), 8 hammer+shield. Per `feedback_grip_offset_sign.md`: -Z raises the grip up the haft, so a more-negative value lifts Kruber's hand higher up the weapon. Skullsplitter (`wpn_wh_1h_hammer_01`) default mesh untouched — it has its own def-level `right_hand_offset = { 0, 0, 0.15 }` for the priest-hammer-on-empire-soldier-bone correction and is unaffected by this change.

## 0.1.197-dev (2026-05-09)
- Fixed: `cwv_es_longsword_shield` right-hand sword mesh wasn't getting the same scale + grip treatment the 2H Imperial Longsword family receives. The variant uses its own `item_type = "cwv_es_longsword_shield"` (so it can carry its own curated shield illusions), so it didn't inherit `_type_transforms.cwv_imperial_longsword`. Added a new `_type_transforms.cwv_es_longsword_shield = { right_hand_scale = {1.0, 0.8, 0.9}, right_hand_offset = {0, 0, -0.065} }` mirroring the 2H family's right-hand values. Sword mesh now matches the longsword silhouette across both 2H and shield variants. Shield (left_hand_unit) untouched.

## 0.1.196-dev (2026-05-08)
- Fixed: `cwv_es_rapier` cosmetic browsing STILL crashed with `[Script Error]: j_leftweaponattach` (crash GUID `77e636ee-f81c-4683-9aae-1f290f4483cd`) — v0.1.192's fix only handled the illusion entries, not the variant's auto-generated DEFAULT skin (`cwv_es_rapier_skin`). Opening the cosmetic picker renders the CURRENT skin first (the default), and the default skin still carried `left_hand_unit = invisible_pistol` from `_register_variant_skins`. The default skin's `matching_item_key = wh_fencing_sword` (per `_register_variant_skins`'s base-weapon convention), so the previewer read the BASE template's full pistol attachment chain and crashed before the user even clicked an illusion.
- Fix: rapier def now declares `no_left_hand = true` (the existing v0.1.179 sentinel from `cwv_es_outrider_grenade_launcher`) and removes the `left_hand_unit = "wpn_invisible_weapon"` line. Effect: `_build_entry` nils `entry.left_hand_unit` on the variant's IML entry; `_register_variant_skins` reads `def.left_hand_unit = nil` and writes `nil` to BOTH the WeaponSkins entry AND the IML weapon_skin entry. The default skin (and combined with v0.1.192, every illusion) has no `left_hand_unit`. Both equip and picker skip the left-hand spawn entirely. No spawn → no node lookup → no crash.
- Tuned: `cwv_es_rapier` Y scale `1.45 → 1.75`, X reverted `1.1 → 1.0`, Z stays at 1.0 — concentrate the broadsword broadening on the depth axis only (cup/basket guard silhouette), no side-profile thickening.

## 0.1.195-dev (2026-05-08)
- Changed: `cwv_es_cudgel` now rides Saltzpyre's falchion moveset (`one_hand_falchion_template_1`) instead of being a stat-tweaked clone of Kruber's mace. Charge-and-release light combo, smiter heavy — but every cutting hit is converted to a crushing one. Same name ("Cudgel"), same Empire mace mesh.
- Damage type swap done by template clone-and-rewrite: each sub-action's slashing damage profile is replaced with its blunt cousin (`light_slashing_axe_linesman` → `light_blunt_tank_diag`, `light_slashing_axe_linesman_upper` → `light_blunt_tank_upper`, `medium_slashing_smiter_1h` → `medium_blunt_smiter_1h`). All three blunt targets are vanilla `DamageProfileTemplates` entries with matching cleave/range/stagger shape.
- Effects/sounds remapped to match: `hit_effect = melee_hit_hammers_1h`, `impact_sound_event = blunt_hit` (and `blunt_hit_armour` for armoured targets), `display_unit = display_1h_hammer` (so the inventory rig holds it like a mace, not a falchion), `sound_event_block_within_arc = weapon_foley_blunt_1h_block_wood`.
- Cross-character anim coverage: falchion is `wh_1h_falchion`'s native template and Kruber already gets cross-access to it via WT, so 3P body anims play correctly without new remap entries.
- Removed the old +20% speed / −15% power / −0.05 reach stat tweaks — the falchion's vanilla pacing is now what defines the weapon's feel.

## 0.1.194-dev (2026-05-08)
- Added: cosmetic illusion options on `cwv_es_sword_and_mace`. Each vanilla `es_1h_sword` skin's mesh is paired with a vanilla `es_1h_mace` skin's mesh — sword on the right hand, mace on the left, matching the variant's inverse-of-vanilla-mace+sword layout. Both source pools have 8 skins; sorted by rarity (common→plentiful→rare→exotic→unique→magic) then zipped by index. 8 illusion entries registered.
- Tier alignment: rarity distributions don't perfectly match (sword has 3 unique + 1 exotic, mace has 2 unique + 2 exotic), so 7 of the 8 pairs share a rarity; one mid-list pair (sword unique × mace exotic) is mismatched. Picker rarity inherits the sword's tier (the right-hand "primary"). Sufficient parity for a clean picker presentation.
- Display rig: `display_dual_weapons` forced on each illusion's IML + WeaponSkins.skins entry (matches the variant's `_force_display_unit` setting; the picker reads display_unit via two paths and needs it on both, per `feedback_cwv_dual_wield_display_rig.md`).

## 0.1.190-dev (2026-05-08)
- Tuskgor Javelin pickup polish (the two cosmetic regressions after v0.1.174 carrier-unit landed):
  - Pickup popup text was showing "Pickup Throwing Axe" (we'd reused `hud_description = "interaction_ammunition_axe"` as a placeholder). Added `cwv_interaction_ammunition_javelin` localization key with text "Tuskgor Javelin" and switched `hud_description` to point at it. Popup now reads correctly.
  - White outline on tagged pickup was missing. Carrier visibility was being toggled via `Unit.set_local_scale(parent, 0, Vector3(0.001, 0.001, 0.001))` which probably also shrank the OutlineExtension's silhouette target. Switched to `Unit.set_unit_visibility(parent, false)` — visibility is a render flag independent of physics actors (interaction stays active because actors aren't affected) and the outline shader may still compute on hidden meshes (the shader's target rect is per-unit metadata, not directly tied to the rendered mesh pass). If outline is still missing after this, the OutlineExtension genuinely needs a visible mesh and we'd need to attach it to the boar spear visual instead.
- Documentation: published `reference_cwv_thrown_weapon_recipe.md` consolidating the v0.1.65 → v0.1.190 Tuskgor Javelin debugging arc into a 7-layer fix stack with end-to-end checklist for adding new cwv thrown weapons. Indexed in MEMORY.md.

## 0.1.193-dev (2026-05-08)
- Fixed: H1 (and consequently H2) of axe+falchion on Kruber didn't play any animation — body stood still on heavy attack. Root cause: chain-context mismatch. The cross-access remap was rewriting H1 to `attack_swing_charge_right` + `attack_swing_heavy_right_diagonal`, but Kruber's mace+sword body has no clips for those events from the **idle** chain state. Per `dual_wield_hammer_sword.lua` (lines 11, 233), Kruber's native idle-heavy chain is `action_one.default` → `charge_left` → `heavy_left_diagonal`; charge_right + heavy_right_diagonal are reachable only via `action_one.default_right_heavy`, the H2 chain state. Body in idle + event the SM "knows but has no clip for in this state" = no animation rendered.
- Fix: swapped H1 and H2 targets in `_kruber_axe_falchion_remap`. H1 now mirrors Kruber's idle-heavy chain (`charge_left` + `heavy_left_diagonal`), H2 mirrors Kruber's chained H2 (`heavy_right_diagonal`). Source axe+falchion's H2 charge is already `attack_swing_charge_left` natively, matching Kruber's H2 charge — no charge remap needed for H2.
- Documented: chain-context rule. The closed-vocabulary rule is necessary but still not sufficient — even an in-vocab event can produce no animation if the body's current chain state has no clip mapped for it. Native chain progression (idle → H1 → H2) drives clip availability.

## 0.1.192-dev (2026-05-08)
- Fixed: `cwv_es_rapier` cosmetic illusion change crashed with `[Script Error]: j_leftweaponattach` (crash GUID `962fe355-a0d4-43fd-9a29-bd64fca6a0ac`). Root cause: `_register_rapier_illusions` set `left_hand_unit = invisible_pistol` on every illusion's IML + WeaponSkins entries. When the player clicked an illusion, the loot previewer's `_load_item_units` saw a non-nil `item_units.left_hand_unit` (per `BackendUtils.get_item_units` line 174 unconditionally overwriting from skin) and tried to spawn `wpn_invisible_weapon_3p` and attach it to the display rig via the BASE template's `pistol.left.third_person.display` linking — and the path crashed in `Unit.node` for `j_leftweaponattach`.
- Fix: `_register_rapier_illusions` now DELIBERATELY omits `left_hand_unit` on illusion entries. With nil left_hand_unit, `BackendUtils.get_item_units` returns nil for left, the previewer's `if left_hand_unit then` branch skips the left-hand spawn entirely (no spawn → no node lookup → no crash). The variant's DEFAULT skin (no illusion picked) still carries `left_hand_unit = invisible_pistol` via the variant's own IML entry — so the no-pistol identity holds on equip with no illusion. With an illusion applied: no left unit at all, and since the pistol was invisible anyway, no visible difference.

## 0.1.191-dev (2026-05-08)
- Tuned: `cwv_es_rapier` Y-axis scale bumped `1.25 → 1.45` (`_type_transforms.cwv_es_rapier`). Per user direction — broaden the depth axis further so the rapier reads as a 17th/18th-century basket-hilt broadsword (chunkier cup/basket guard silhouette) instead of a thin reikland duellist's blade. X stays at +10%, Z native. Type-level so default + every `wh_fencing_sword_skin_*` illusion inherits.

## 0.1.189-dev (2026-05-08)
- Removed: `cwv_es_brace_repeater` variant (Repeater Brace) and the entire 3P-unit-override mechanism it required (`right_hand_unit_3p_override` / `left_hand_unit_3p_override` def fields, `_resolve_3p_override` lookup helper, `_3p_swap_enabled` setting gate, `cwv_3p_swap_enabled` toggle, the `GearUtils.spawn_inventory_unit` hook). Per user direction, the brace-on-Kruber idea moved to weapon_tweaker — now lives there as a 3P unit swap on Kruber's vanilla `wh_brace_of_pistols` cross-access. No separate inventory item; the player wields the standard brace on Kruber and the 3P body shows the repeater. See `weapon_tweaker` v0.12.2 for the receiving end.
- Removed bits also dropped from `_seed_targets`, `_item_type_to_skin_table`, `_create_brace_repeater_template`, `_BRACE_REPEATER_*` constants, and the `cwv_3p_swap_enabled` setting from `_data.lua` + `_localization.lua`.
- Migration breadcrumbs: short comments left at the variant-def site and the swap-hook site pointing at weapon_tweaker for anyone reading old code.

## 0.1.188-dev (2026-05-08)
- Fixed: `cwv_es_maul` crashed on inventory open / preview with `[Script Error]: a_unwielded_brw_mace` (crash GUID `258c5f1c-dbe0-4ebd-8ef6-0b43d95c3b9d`). Same family as the v0.1.187 rapier `lock_hammer` crash but on the BODY skeleton this time — `a_unwielded_brw_mace` is a bone authored ONLY on Sienna's 3P body for her holstered-mace pose. v0.1.167 already overrode the CLONED template's `right_hand_attachment_node_linking` for in-game equip; missing piece was the inventory previewer, which reads the BASE template per `feedback_cwv_previewer_template_lookup.md`.
- Fix: `_create_maul_template` now also patches the BASE `one_handed_hammer_wizard_template_1.right_hand_attachment_node_linking.third_person.unwielded` to `j_hips → 0`. Wielded slot left untouched (uses universal `j_rightweaponattach`), so Sienna's in-hand mace behavior is unchanged. Cost: Sienna's holstered-mace pose now sits on standard hips instead of her dedicated mace bone — minor visual regression on her side, fixes Kruber preview crash. Verified via source-wide grep that `AttachmentNodeLinking.brw_hammer` is referenced by only this one template, so the patch is well-scoped.

## 0.1.187-dev (2026-05-08)
- Fixed: `cwv_es_rapier` crashed on equip with `[Script Error]: lock_hammer` (GUID `acb910d1-a625-49b1-b899-86d48d27462d`). Root cause: `fencing_sword_template_1.left_hand_attachment_node_linking = AttachmentNodeLinking.pistol.left`, which has component bindings for `lock_hammer`, `trigger`, `lock_lid` — node names that exist on `wpn_emp_pistol_01_t1` (Saltzpyre's pistol) but NOT on `wpn_invisible_weapon` (our variant's left mesh, since we removed the pistol). Vanilla `Unit.node(invisible_weapon, "lock_hammer")` crashes hard on missing nodes.
- Fix: `_create_rapier_template` now overrides `template.left_hand_attachment_node_linking` to a minimal binding (`j_leftweaponattach → 0` for first/third person wielded, `j_hips → 0` for unwielded). No component lookups, no crash. Patch is on the CLONE only — base `fencing_sword_template_1` keeps its full pistol bindings intact for native Saltzpyre wielders.
- Documented: same failure pattern (`Unit.node` lookup crash on a mesh that doesn't have the bound target node) generalizes to ANY variant that swaps a multi-component weapon's hand to `wpn_invisible_weapon` or a different mesh family. Add to RECIPES.md "Disable a weapon special action add-on" — the off-hand mesh swap pattern needs to also strip component bindings from the cloned template's `<hand>_hand_attachment_node_linking`.

## 0.1.186-dev (2026-05-08)
- Flipped: `cwv_3p_swap_enabled` setting `default_value = false → true`. v0.1.183 set the gate to OFF as a stability hedge while the swap path was unproven; v0.1.184's upstream fix to `_register_variant_skins`'s `ammo_unit` fallback removed the underlying equip crash, so the swap is safe to enable by default. Effect: `cwv_es_brace_repeater` now shows the **repeater** model in 3P (correct, matches the anim + sound + effect) instead of the **brace of pistols** (the 1P mesh that was leaking through to 3P with the swap disabled). Existing user profiles that explicitly toggled the setting OFF will still see brace in 3P — flip the toggle in mod settings to pick up the swap.

## 0.1.185-dev (2026-05-08)
- Fixed: `cwv_es_outrider_grenade_launcher` right-click crashed with `player_character_state_helper: tried to start a left hand weapon action without a left hand wielded unit` (GUID `33e82f2c`). Multiple inherited trollhammer actions are left-handed because Bardin holds the trollhammer in his left hand: `action_one.push` (`weapon_action_hand = "left"`), `action_inspect = ActionTemplates.action_inspect_left`, `action_wield = ActionTemplates.wield_left`. Our variant has `no_left_hand = true` (right-handed blunderbuss mount), so the engine couldn't find a left-hand wielded unit to back the action. Fix:
  - **Right-click bash now mimics the blunderbuss.** Per user request — copied `Weapons.blunderbuss_template_1.actions.action_two` (the shield-slam shotgun bash, `kind = "shield_slam"`, `damage_profile = "shield_slam_shotgun"`, no `weapon_action_hand` set so it's right-hand-compatible) onto `template.actions.action_two`. Right-click now produces a satisfying explosive bash matching the blunderbuss's identity.
  - **Inspect / wield swapped to right-handed** — `ActionTemplates.action_inspect` and `ActionTemplates.wield` (no `_left` suffix).
  - **Dropped trollhammer's chained `action_one.push`** — replaced by the new `action_two` bash.
- Documentation: rolled up this session's recurring lessons into DEVELOPMENT.md and a new memory note. New DEVELOPMENT.md sections: "BASE template patching for previewer compatibility" (the v0.1.181 lesson — previewer reads BASE, so any field the variant uses but the base doesn't must be patched onto the base), "Cross-template Frankenstein weapons (visual ≠ behavior)" (the outrider recipe + visual-layer-override + hand-mount-swap pattern), "`no_left_hand` / `no_right_hand` def flag" (the v0.1.181 flag — explicit clearer for inherited base hand model), "Skin entry fallbacks — gate on base presence" (the v0.1.184 ammo_unit lesson — gate fallbacks on the base weapon actually using the assumed field). New memory: `feedback_cwv_frankenstein_template.md`. Updated memory: `feedback_cwv_ammo_unit_required.md` with the gating rule.

## 0.1.184-dev (2026-05-08)
- Fixed: `cwv_es_brace_repeater` (and any future cwv variant whose base weapon doesn't define `ammo_unit`) crashed on equip with `GearUtils.spawn_inventory_unit fassert: ammo unit defined in weapon without attachment node linking` → propagating to `simple_inventory_extension: attempt to index local 'slot_equipment_data' (a nil value)` (crash GUID `2df233ae-80f6-40d3-aa58-e98417f2ad8f`). Root cause: `_register_variant_skins` defaulted `ammo_unit = def.ammo_unit or def.left_hand_unit` — a fallback that was correct for thrown variants like `cwv_es_javelin` (where `we_javelin` IML has `ammo_unit` set), but WRONG for variants whose base weapon has no ammo_unit at all (`wh_brace_of_pistols`). When our variant force-set the pistol mesh as ammo_unit, the brace's vanilla template — which has `ammo_data.ammo_hand = "right"` but no `ammo_unit_attachment_node_linking` — triggered the spawn-time assertion. Fix: gate the fallback on `base.ammo_unit` existing — only inherit the held mesh as ammo_unit when the base weapon already uses one. Preserves the javelin/spear path; nukes the spurious ammo_unit on brace/pistol-family variants.
- Complements v0.1.183's symptom-side fix on `_cwv_3p_unit_override_swap` (hardened spawn hook returns vanilla on any pcall failure, so create_equipment never returns nil even if a 3P swap raises). v0.1.184 fixes the upstream cause; v0.1.183's hardening still serves as defense in depth for unrelated future swap paths.

## 0.1.183-dev (2026-05-08)
- Hardened: `_cwv_3p_unit_override_swap` hook on `GearUtils.spawn_inventory_unit`. Previous structure could leave `GearUtils.create_equipment` returning nil when the swap path errored, causing `simple_inventory_extension.add_equipment` to crash with `attempt to index local 'slot_equipment_data' (a nil value)` (GUID 3c05218c). Rewrote to ALWAYS call vanilla first, capture all 4 return values, then attempt the swap inside an outer pcall. On any pcall failure or sentinel result, return vanilla's unmodified units — equipping never fails because of the swap. Spawn-override-then-destroy-vanilla order swapped: spawn override FIRST, only mark vanilla 3P unit for deletion if the override spawn succeeded (avoids stranding the equip with no 3P unit).
- Added: VMF setting `cwv_3p_swap_enabled` (default OFF). The `cwv_es_brace_repeater` 3P unit-swap mechanism is gated on this setting. Default OFF until the swap path is proven stable. With setting OFF, the variant equips and works as a regular Saltzpyre brace of pistols on Kruber (no 3P swap, no anim redirect side effects).
- Known issue (still open): when the swap setting is ON, the v0.1.180 attempt crashed on equip. Likely cause is the override 3P unit (`wpn_emp_handgun_repeater_t1_3p`) not being in the loaded inventory package for a brace-of-pistols equip — same package-loading pattern that affected the Tuskgor Javelin's elf javelin pickup unit (CHANGELOG v0.1.118). Resolution path: either add the repeater unit as a static dependency of the cwv mod's resource_packages, or force-load the repeater package at runtime before spawn. Deferred to a future build.

## 0.1.181-dev (2026-05-08)
- Fixed: `cwv_es_outrider_grenade_launcher` crashed in inventory preview with `world_hero_previewer.lua: attempt to index field 'right_hand_attachment_node_linking' (a nil value)` (crash GUID `c847908d-c1e0-46be-8d15-c45c2a80e8a0`). Two compounding issues:
  1. The previewer reads `ItemHelper.get_template_by_item_name(item_name)` where item_name is the BASE weapon's name (cwv variants inherit `entry.name` per `feedback_cwv_clone_name_clobber.md`), so it gets `dr_deus_01_template_1` — NOT our cloned `outrider_grenade_launcher_template`. Vanilla `dr_deus_01_template_1` only has `left_hand_attachment_node_linking` set (Bardin's trollhammer is left-hand-mount; his `right_hand_unit` is nil natively, so the previewer's right-hand path never fires for him). For our cwv variant on Kruber, `right_hand_unit` IS set (the blunderbuss mesh), so the right-hand path fires and crashes on missing `right_hand_attachment_node_linking`. Fix: patch the BASE template at the end of `_create_outrider_grenade_launcher_template` to add `right_hand_attachment_node_linking = AttachmentNodeLinking.rifles`. Bardin still doesn't reach the right-hand path natively, so this is harmless for vanilla trollhammer. Same pattern as v0.1.84 elf shield wield routing — patch BASE template too because previewer ignores clones (`feedback_cwv_previewer_template_lookup.md`).
  2. The variant inherited `left_hand_unit = "...wpn_dr_deus_01"` from the trollhammer clone (since Bardin mounts the gun on the left hand). With `right_hand_unit` set to the blunderbuss mesh, BOTH would render → Kruber would visually wield TWO weapons in the preview. Added a new `def.no_left_hand = true` flag to `_build_entry` that explicitly nils out the inherited `left_hand_unit`. Distinct from `def.left_hand_unit = nil` (which the existing override gate treats as "don't override" → inheritance kicks in). Applied to the outrider def.

## 0.1.180-dev (2026-05-08) — WIP, user testing
- Added: `cwv_es_brace_repeater` ("Repeater Brace") — experimental variant on all 4 Kruber careers, exotic. **First CWV variant with different 1P and 3P meshes.** From the player's first-person view, looks and animates like Saltzpyre's brace of pistols (cross-arm fire, two-handed reload). To other players (3P body) and in inventory preview, renders as Kruber's repeating handgun and plays his 3P repeater animations.
- Added: per-perspective unit-swap mechanism. Two new optional def fields — `right_hand_unit_3p_override` / `left_hand_unit_3p_override` — declare a different 3P unit path. New hook `_cwv_3p_unit_override_swap` on `GearUtils.spawn_inventory_unit` lets vanilla spawn the 1P + default 3P units, then destroys the just-spawned 3P unit and replaces it with the override. Fires for BOTH local equip and husk spawn paths (same vanilla function), so other players see the swap too.
- `*_3p_override = false` is a sentinel meaning "no 3P unit for this hand" — used when the 3P weapon is single-handed but the 1P weapon is dual (Repeater Brace: two pistols 1P → one repeater 3P).
- Animation: brace and repeater templates share most event names (`attack_shoot`, `attack_shoot_fast`, `lock_target`) so the per-action 3P remap is minimal — only `special_action` (brace's "fire all 8 pistols" finisher) routes to `attack_shoot_fast`. 3P wield routes to `to_repeating_handgun` for Kruber careers.
- Caveats: 1P brace reload anim and 3P repeater reload anim have different durations; gameplay timing follows 1P, so the two perspectives visually desync during reloads. Cosmetic illusions intentionally not implemented in v1 — verify the swap mechanism works first.

## 0.1.179-dev (2026-05-08) — WIP, user testing
- Added: `cwv_es_outrider_grenade_launcher` ("Outrider Grenade Launcher") — Frankenstein weapon. Bardin Engineer's Trollhammer Torpedo behavior (`dr_deus_01_template_1`) wrapped in Kruber's blunderbuss visual layer. All 4 Kruber careers, exotic. Right hand uses the Empire blunderbuss model (`wpn_empire_blunderbuss_t1`). Pulls in the trollhammer's grenade-thrower action (single-shot explosive projectile, charge-and-release mechanics, blast damage) but renders + animates as Kruber wielding a blunderbuss.
- Cross-character anim works because the trollhammer template's `action_one.default.anim_event = "attack_shoot"` is also a blunderbuss state-machine event — Kruber's empire-soldier 3P body authors `attack_shoot` natively (his vanilla blunderbuss uses it). No per-action remap needed.
- Visual layer overrides applied in `_create_outrider_grenade_launcher_template`: state_machine → `ranged/blunderbuss`, wield_anim → `to_blunderbuss`, display_unit → `display_blunderbusses`, right_hand_attachment_node_linking → `AttachmentNodeLinking.rifles`. Hand swap from trollhammer's left-hand mount to right-hand: every `weapon_action_hand` and `ammo_data.ammo_hand` flipped to "right"; `left_hand_unit` cleared, `wwise_dep_left_hand` moved to `wwise_dep_right_hand`.
- Tunes vs vanilla trollhammer: speed 2500 → 3500 (faster projectile, "travels further/faster"), reload_time × 0.65 (~35% faster reload), damage profile cloned with `damage = 0.65, stagger = 0.65` multipliers (proportionally smaller damage), max_range 20 → 30 (longer aim-assist reach).
- WIP / TODO (per user "I'll have to test"): explosion radius not tuned yet — `ExplosionTemplates.dr_deus_01` isn't in the decompiled source we work from, so the explosion template runs at vanilla trollhammer radius. Smaller-radius tune is a follow-up once the user tests current behavior. Projectile model is also still the trollhammer torpedo — user wants a grenade-shaped projectile, follow-up after testing.

## 0.1.178-dev (2026-05-08)
- Added: `cwv_es_rapier` ("Rapier") — Saltzpyre's `wh_fencing_sword` template (`fencing_sword_template_1`) cloned for all 4 Kruber careers, exotic. Right hand: `wpn_fencingsword_01_t1` (the rapier). Left hand: invisible — pistol mesh removed.
- Pistol-shoot ability disabled: `_create_rapier_template` overrides `action_three.*.condition_func` and `chain_condition_func` to `_always_false`. Action stays defined for state-machine / network consistency but never fires (same pattern as the tuskgor javelin's auto-catch reload disable in v0.1.65).
- Animation: 3P wield routes to Kruber's native `to_1h_sword` SM via `wield_anim_3p` + per-career override; base-template patch on `fencing_sword_template_1.wield_anim_career_3p` for previewer fidelity per `feedback_cwv_previewer_template_lookup.md`. Closed-vocabulary 3P remap (3 entries) covers fencing-specific events (`attack_swing_stab_charge`, `attack_swing_stab`, `attack_swing_left`) not authored on `one_handed_swords_template_1`'s vocabulary.
- Type-level scale `_type_transforms.cwv_es_rapier = { right_hand_scale = {1.1, 1.25, 1.0} }` broadens X/Y for a basket-hilt feel; Z stays native.
- Curated illusions: `_register_rapier_illusions` clones every `wh_fencing_sword_skin_*` onto the Rapier variant. Each illusion forces `left_hand_unit = "units/weapons/player/wpn_invisible_weapon"` so the variant's "no pistol" identity holds across all cosmetic options (source skins always carry a pistol mesh).
- Wired: `cwv_es_rapier` into `_seed_targets` and `_item_type_to_skin_table`.
- Placeholder icons (vanilla fencing-sword icons) — variant is NOT complete until custom icons are authored.

## 0.1.177-dev (2026-05-08)
- Fixed: `cwv_es_maul` cosmetic picker was showing every `es_1h_mace_skin_*` (Kruber's standard 1H flanged maces) — wrong source. The Maul is supposed to be "the club from the mace+sword's mace half", so its illusions should only come from `es_dual_wield_hammer_sword` skin variants. Replaced `_register_kruber_1h_mace_maul_illusions` with `_register_macesword_mace_maul_illusions`: scans `matching_item_key == "es_dual_wield_hammer_sword"` skins, takes only the `right_hand_unit` (mace half), discards `left_hand_unit` (sword half — doesn't belong on a Maul). Forces single-rig `display_1h_hammer` since the mace+sword's source rig authors both attach nodes. Picker now shows ~3-4 chunky mace heads (skin_01 / 02 / 02_runed_01 / 02_magic_01) instead of 11+ smaller flanged maces.

## 0.1.176-dev (2026-05-08)
- Tuned: `cwv_es_maul` grip offset — added `right_hand_offset = { 0, 0, 0.5 }` to `_type_transforms.cwv_es_maul`. Hand was riding too high up the haft (toward the mace head); +Z lowers the grip per `feedback_grip_offset_sign.md`. Type-level so default mesh + every `es_1h_mace_skin_*` illusion inherit the same correction.

## 0.1.175-dev (2026-05-08)
- Added: `cwv_es_longsword_shield` (Imperial Longsword and Shield) — clone of `es_sword_shield_breton` (Grail Knight's Bretonnian sword+shield, `one_handed_sword_shield_template_2`) on all 4 Kruber careers, exotic. Right hand uses the Recruit Longsword mesh (`wpn_2h_sword_04_t1`); left hand uses the standard Empire shield (`wpn_emp_shield_02`). The Bretonnian template's animations work on all Kruber careers natively (proven by weapon_tweaker's existing `es_sword_shield_breton` cross-access on Mercenary/Huntsman/Knight) — no anim remap or wield routing needed.
- Added: cosmetic illusion picker registers every unique shield (`left_hand_unit`) from the vanilla `es_sword_shield` skin pool — Empire Shield 01_t1 / 02 / 03 / 04 / 05 plus 02_runed_01 / 03_runed_01. Each illusion keeps the same Imperial Longsword right hand and swaps the shield. Deduped by mesh path so multiple skins sharing a shield mesh don't produce duplicate picker entries.
- Wired: `cwv_es_longsword_shield` into `_seed_targets` and `_item_type_to_skin_table`. Display rig is `display_shield_sword` (vanilla Bretonnian template's default — fits 1H sword + shield correctly), so no `_force_display_unit` entry needed. DLC gating (`required_dlc = "lake"`) is stripped by `_build_entry`'s standard pass.

## 0.1.173-dev (2026-05-08)
- Fixed: cwv variants without an explicit `def.item_type` displayed the BASE weapon's name in vanilla UI labels that read `Localize(item_data.item_type)` — e.g. `cwv_es_shortsword` showed as "Dagger" (Sienna's bw_dagger) in loot drop banners and the cosmetics inventory header, even though the illusion correctly showed "Shortsword". Root cause: `_build_entry` only set `entry.item_type` when `def.item_type` was explicit; otherwise the inherited base-weapon item_type came through (per `feedback_cwv_clone_name_clobber.md`, name/key are inherited on purpose). Now `entry.item_type` is always set to `def.item_type or def.item_key`, and `_display_names[item_type]` always maps to `def.display_name` — so every UI element that resolves the weapon-type label gets the cwv name.
- Affected variants (those without explicit def.item_type that needed the fallback): `cwv_es_axe_shield`, `cwv_we_sword_shield`, `cwv_es_priest_greathammer`, `cwv_dr_priest_greathammer`, `cwv_es_javelin`, `cwv_wh_javelin`, `cwv_es_longsword_blackguard` (and other unique skin-only variants), `cwv_es_cudgel`, `cwv_es_shortsword`. Variants that already set `def.item_type` (`cwv_imperial_longsword` family, dual-wield variants, `cwv_es_warpriest_hammer`, `cwv_es_sword_and_mace`, etc.) are unchanged. Title-case fallback (`def.item_type:gsub(...)`) replaced with `def.display_name` for cleaner labels — the auto-derived "Es Dual Axes" / "Imperial Longsword" strings become just the user-friendly display name.

## 0.1.172-dev (2026-05-08)
- Tuned: `cwv_es_maul` scale `{1.4, 1.4, 2.0} → {1.075, 1.075, 1.4}` per user (v0.1.168 was too big — the X/Y bump made the 1H mace look inflated; new values keep proportions tighter while still adding enough Z length to read as a 2H maul).
- Tuned: `cwv_es_poleaxe` grip offset `right_hand_offset = {0, 0, 0.5}` per user — the +Z lowers Kruber's grip onto the haft (the vanilla halberd grip rode too high after the Z-shrink). Per `feedback_grip_offset_sign.md`, +Z = grip lower.
- Tuned: `cwv_es_poleaxe` stats — speed × 1.20 (faster than greataxe baseline; poleaxe is a lighter polearm), power × 0.85 (less damage and stagger than a full greataxe). Applied per sub-action via `_clone_damage_profile` + `anim_time_scale` mult, parallel to the cudgel/shortsword pattern.

## 0.1.170-dev (2026-05-08)
- Fixed: vanilla `es_dual_wield_hammer_sword` (Mace and Sword) was not being renamed to "Cudgel and Short Sword" in the inventory unless the player had the default `skin_01` illusion applied. The Localize hook keyed on `es_dual_wield_hammer_sword_skin_01_name` exactly, but VT2's inventory and cosmetic UIs read the APPLIED SKIN's display_name key — which becomes `_skin_02_name`, `_skin_02_runed_01_name`, etc. when the user applies any non-default illusion. So players who'd ever applied a different illusion saw "Mace and Sword" (the skin's per-key vanilla localization) instead of the renamed "Cudgel and Short Sword". Switched the hook to a prefix+suffix pattern match (`es_dual_wield_hammer_sword_skin_…_name`) so every illusion variant gets the renamed name. Toggle (`mace_sword_tweak`, default ON) still gates the behavior.

## 0.1.169-dev (2026-05-08)
- Fixed: `cwv_es_maul` crashed Kruber on unequip with `[Script Error]: a_unwielded_brw_mace` (crash GUID `37ead770-8f34-4821-b71d-2de354929a80`). Root cause: the wizard 1H mace template (`one_handed_hammer_wizard_template_1`, the source `_create_maul_template` clones from) sets `right_hand_attachment_node_linking = AttachmentNodeLinking.brw_hammer`. That linking specifies `unwielded.source = "a_unwielded_brw_mace"` — a bone authored only on Sienna's 3P body skeleton. When Kruber tries to sheath the maul, `Unit.node()` looks for the bone on his empire-soldier body, doesn't find it, crashes (same shape as the v0.1.122–v0.1.145 `j_leftweaponattach` saga). Fix: override the cloned template's `right_hand_attachment_node_linking` to `AttachmentNodeLinking.two_handed_melee_weapon`, which uses `a_unwielded_2h` for sheath (Kruber-compatible) and `j_rightweaponattach` for wielded (same as before). Maul is visually 2H (1.4×1.4×2.0 scale) so 2H linking matches both the silhouette and Kruber's skeleton.

## 0.1.168-dev (2026-05-08)
- Added: `cwv_es_maul` ("Maul") — Sienna's `bw_1h_mace` Morningstar template cloned for all 4 Kruber careers. Default mesh `wpn_emp_mace_04_t2` (Kruber's mace+sword mace); curated illusions register every vanilla `es_1h_mace_skin_*` via new `_register_kruber_1h_mace_maul_illusions`. Type-level scale `{1.4, 1.4, 2.0}` (`_type_transforms.cwv_es_maul`) inflates the 1H mesh into a 2H silhouette across default + every illusion.
- Damage-type swap (Maul): `_create_maul_template` clones `one_handed_hammer_wizard_template_1` and swaps H1 heavy attack's `damage_profile` from `medium_blunt_smiter_heavy` → `medium_blunt_smiter_2h_hammer`. Wizard fire is in the damage-profile resolution chain, NOT the FX/sound fields — the chain `medium_blunt_smiter_heavy.default_target = "default_target_slashing_smiter_burn_M"` (line 463 of `damage_profile_templates.lua`) is the only `_burn_*` reference reachable from the wizard mace's actions. Lights, H2/H3, pushes are clean (verified). FX/sound fields already non-fire (`melee_hit_hammers_1h` / `blunt_hit`) — no FX swap pass needed.
- Animation (Maul): 3P wield routes to Kruber's greathammer SM (`to_2h_hammer`); base-template patch on `one_handed_hammer_wizard_template_1.wield_anim_career_3p` for previewer fidelity per `feedback_cwv_previewer_template_lookup.md`. Closed-vocabulary 3P remap (9 entries) covers wizard-mace events not in `two_handed_hammers_template_1`'s authored vocabulary.
- Added: `cwv_es_poleaxe` ("Poleaxe") — Bardin's `dr_2h_axe` Greataxe template cloned for all 4 Kruber careers. Default mesh `wpn_wh_halberd_01` (Kruber's halberd); curated illusions register every vanilla `es_halberd_skin_*` via new `_register_halberd_poleaxe_illusions`. Type-level scale `{1.0, 1.0, 0.65}` (`_type_transforms.cwv_es_poleaxe`) shortens the halberd's Z so it reads as a polearm rather than a full halberd.
- Animation (Poleaxe): no `wield_anim_3p` patch needed — `two_handed_axes_template_1` already wields to `to_2h_hammer` natively, which Kruber's body authors. Closed-vocabulary 3P remap (3 entries) covers `attack_swing_heavy_*_diagonal` and `attack_swing_up` (greataxe events not in greathammer vocabulary).
- Added: dynamic-illusion transform inheritance pass after `_skin_transform_map` builder (line ~4660). Iterates `_custom_skin_keys`, finds keys matching a known variant prefix, and injects the variant's def into `_skin_transform_map[skin_key]` so cosmetic-picker previews of dynamic illusions inherit the type-level scale. In-game render path was already correct via the backend_id fallback in `_resolve_cwv_def`; this fixes the picker pane only.
- Both variants ship with **placeholder icons** (Sienna mace icon for the Maul, vanilla halberd icon for the Poleaxe). Variants are NOT considered complete until custom inventory + HUD icons are authored — see `RECIPES.md` "Icons — completion gate".
- Docs: `RECIPES.md` updated with the source-verification preflight (don't trust profile names — walk the resolution chain), the Damage-type swap "Step 0 — find the fire" subsection, the type-level vs per-illusion scale decision rule, and the icons-completion gate. Two real failure modes documented: weapon names lying about slot type (`bw_1h_mace` is wielded 2-handed despite the "1h" naming), and damage-profile names lying about fire content (`medium_blunt_smiter_heavy` resolves through `_burn_*` PowerLevelTemplates).

## 0.1.167-dev (2026-05-08)
- Added: `cwv_es_warpriest_hammer_shield` (Warrior-Priest Hammer and Shield) — clone of Saltzpyre's Bless DLC `wh_hammer_shield` (priest 1H hammer + shield) on Kruber, all 4 careers. Right hand `wpn_wh_1h_hammer_01` (Skullsplitter), left hand `wpn_emp_shield_02` (Empire shield). Pairs with the existing 1H `cwv_es_warpriest_hammer` and dual `cwv_es_dual_warpriest_hammers` to give Kruber the full Skullsplitter family.
- Animation routing: added `one_handed_hammer_shield_priest_template` to `_cross_access_template_wield_3p` — Kruber routes to `to_1h_hammer_shield` (his vanilla mace+shield wield SM). Direct Kruber equivalent of weapon_tweaker's `to_1h_hammer_shield_priest → to_1h_hammer_shield` redirect at `weapon_tweaker.lua:231`.
- Grip offset: `right_hand_offset = {0, 0, 0.15}` — same Skullsplitter haft riding-high correction used by the 1H and dual variants. Mirrors weapon_tweaker's `wh_hammer_shield = { es_ = {0,0,0.15} }` tune.
- Wired: `cwv_es_warpriest_hammer_shield` into `_seed_targets`, `_item_type_to_skin_table`, and `_force_display_unit` (→ `display_shield_hammer`, matching the priest hammer+shield template default).
- Migrated: 8 rescaled greathammer cosmetic illusions (originally on `cwv_es_warpriest_hammer` in v0.1.157) onto BOTH `cwv_es_dual_warpriest_hammers` (mirror right→left) and `cwv_es_warpriest_hammer_shield` (right hand greathammer, left hand Empire shield via override). 16 new illusion entries — same rescaled scale `{0.75, 0.75, 0.575}` and offset `{0, 0, -0.04}` per hand.
- Extended: `_register_custom_illusions` with two new illusion-entry fields. `mirror_to_left = true` mirrors the source's right_hand_unit into left_hand_unit for identical-mesh dual-wield targets (varies per source, can't be hardcoded). `display_unit_override` forces a specific display rig on the cloned skin, required when the source's rig doesn't author both attach nodes for the target's slot shape (greathammer source uses `display_2h_swords` single-rig, but our dual / shield targets need `display_dual_hammers` / `display_shield_hammer`). See `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the rule.

## 0.1.166-dev (2026-05-08)
- Added: `cwv_es_shortsword_shield` (Shortsword and Shield) — clone of `es_mace_shield` enabled on all 4 Kruber careers. Right-hand mace becomes a Reikland shortsword (`wpn_emp_sword_06_t1`), left-hand shield uses Kruber's standard `wpn_emp_shield_02` by default.
- Added: `shortsword_shield_template` clone of `one_handed_hammer_shield_template_1` with per-sub-action stat tweaks. Sweep attacks: speed × 1.20, damage × 1.0, stagger × 0.9. Damage profile swaps per user (decided one-by-one in v0.1.166): `medium_blunt_tank_1h → medium_slashing_linesman_1h` (heavy, cleaving + heavy_attack armor pen but linesman armor profile = less potent than tank), `light_blunt_tank → light_slashing_linesman` (light L), `light_blunt_tank_diag → light_slashing_linesman` (light D, matches sword_and_mace), `light_blunt_smiter → light_slashing_smiter` (smiter overheads). Mace FX/sounds → sword equivalents. Heavy 1 (shield bash, `kind = "shield_slam"`), push, and block intentionally untouched — those are shield/non-weapon-specific actions and keep their vanilla mace+shield behavior.
- Added: rarity-tier-paired sword+shield illusions on `cwv_es_shortsword_shield` via `_register_shortsword_shield_illusions`. For each vanilla `es_1h_sword_skin_*` source (sword right hand), the cloned skin's left hand gets a shield drawn from the `es_mace_shield` skin pool of the same rarity (round-robin within the tier, falling back to `wpn_emp_shield_02` for tiers without a same-rarity shield). Curated picker — not the cartesian product of every-sword × every-shield.
- Wired: `cwv_es_shortsword_shield` into `_seed_targets`, `_item_type_to_skin_table`, and `_force_display_unit` (→ `display_shield_sword`, since the variant clones from `es_mace_shield` whose template defaults to `display_shield_hammer` — wrong rig for the new sword right hand).

## 0.1.165-dev (2026-05-08)
- Tuned: `cwv_es_shortsword` speed multiplier `0.80 → 0.92`. The original −20% slowdown was set when the variant still had Sienna's burning damage profiles giving it DoT value to compensate; v0.1.155+ stripped the DoT so a 20% speed penalty no longer matched the trade-off. New −8% slow keeps it a touch heavier than the dagger (the model is a Reikland shortsword, not a finesse blade) without feeling sluggish. Power untouched at +15%.

## 0.1.164-dev (2026-05-08)
- Tuned: `cwv_es_cudgel` reach −0.05 on every sweep (uniform delta on the inherited es_1h_mace `range_mod` per sub-action). Light attacks 1.20 → 1.15, heavy 1.30 → 1.25. Lighter mace = shorter haft / shorter wrist arc — keeps the cudgel meaningfully shorter than the standard `es_1h_mace`. Implemented as a `_CUDGEL_RANGE_DELTA = -0.05` additive in `_create_cudgel_template`'s sub-action walk, guarded on `sub_action.range_mod` existing so non-sweep actions are untouched.

## 0.1.163-dev (2026-05-08)
- Tuned: `cwv_es_sword_and_mace` per-hand reach. Vanilla `dual_wield_hammer_sword` runs at `range_mod = 1.15` for right-hand mace sweeps and `1.1` for left-hand sword sweeps — shorter than the 1h equivalents because dual-wield reads tighter. Per user request, the variant now matches each 1h source's light-attack reach: right hand (sword in our variant) → `1.2` (matches `es_1h_sword` / `one_handed_swords_template_1`); left hand (mace in our variant) → `1.2` (matches `es_1h_mace` / `one_handed_hammer_template_1`). Both numerically land at `1.2` because that's what each 1h template uses for its light attacks; the heavies in the dual template are `weapon_action_hand = "both"` and untouched (their range comes from the dual baseline since both weapons are involved).
- Implemented via new `_SAM_HAND_RANGE_MOD` table + an unconditional override in `_create_sword_and_mace_template`'s action walk (parallel to the existing damage/sound/effect swaps but using direct assignment instead of value-keyed lookup, since range_mod is numeric not a string id). Guarded on `sub_action.range_mod` existing so non-sweep sub-actions (push, block) don't get a stray range_mod field.

## 0.1.162-dev (2026-05-08)
- Added: `cwv_es_dual_warpriest_hammers` (Dual Warrior-Priest Hammers) — paired clone of Saltzpyre's vanilla Bless DLC `wh_dual_hammer`, enabled natively on all 4 Kruber careers. Right and left hand both use the `wpn_wh_1h_hammer_01` Skullsplitter mesh. Pairs with the v0.1.157 single-hand `cwv_es_warpriest_hammer` to give Kruber a dual-Skullsplitter loadout.
- Animation routing: added `dual_wield_hammers_priest_template` entry to `_cross_access_template_wield_3p` — Kruber careers route to `to_dual_hammer_sword_es` (his mace+sword SM, same approach `cwv_es_dual_maces` uses for non-priest dual hammers). The priest template's default wield event `to_dual_hammers_priest` is only authored on Saltzpyre's wh_priest 3P body. The Kruber-specific equivalent of weapon_tweaker's `to_dual_hammers_priest → to_dual_hammers` redirect (which targets Bardin's body, where `to_dual_hammers` exists natively).
- Grip offset: `right_hand_offset = left_hand_offset = {0, 0, 0.15}` per hand. Mirrors weapon_tweaker's `wh_1h_hammer = { es_ = {0, 0, 0.15} }` tune for the same mesh on the same body — the Skullsplitter rides high on the empire-soldier hand bone without the +Z lower-onto-haft correction (per `feedback_grip_offset_sign.md`).
- Wired: `cwv_es_dual_warpriest_hammers` into `_force_display_unit` (→ `display_dual_hammers`, vanilla precedent: `dual_wield_hammers_priest.lua:1720`), `_seed_targets`, and `_item_type_to_skin_table`. Cosmetic picker shows curated default only; cross-character illusions can be added later if desired (e.g. cloning vanilla `wh_dual_hammer_skin_*` or `es_1h_mace_skin_*` onto this picker).

## 0.1.161-dev (2026-05-08)
- Added: `attack_swing_down → attack_swing_left` entry to `_kruber_axe_falchion_remap`. Source push-attack (`light_attack_bopp` fires `attack_swing_down`) IS in target's closed vocab, but target's clip is a downward mace chop (right-hand). User wants the push-attack to read as a left-hand falchion swing, so remap to `attack_swing_left` (target's `light_attack_left`) — closest left-hand horizontal swing in the closed list.
- Refined: `ANIMATION_FIX_PLAYBOOK.md` and `feedback_anim_closed_vocabulary.md` — clarified that "in target vocab" is necessary but not sufficient. The target's *clip* for that event still has to match the visual intent; if not, pick a different in-vocab event. Updated Step 4 cross-reference table with a new column for "matches intent?" and added a worked example for the push-attack case.

## 0.1.159-dev (2026-05-08)
- Added: vanilla empire 1h-mace skins as cosmetic illusion options on BOTH `cwv_es_dual_maces` (Kruber) and `cwv_wh_dual_maces` (Saltzpyre). Mirrors the v0.1.152 pattern: each `ItemMasterList` entry with `matching_item_key = "es_1h_mace"` is cloned into `cwv_es_dual_maces_<source_key>` and `cwv_wh_dual_maces_<source_key>` and registered into the variant's curated picker. Both hands use the source mesh; `display_dual_hammers` rig forced (vanilla precedent: `weapon_skins_bless.lua:395`).
- Implemented via new `_register_es_1h_mace_dual_illusions` function — single pass over the source skin set, registers into both target variants per `_targets` table (Kruber → `_es_all_careers`, Saltzpyre → `_wh_all_careers`). Cleaner than two parallel single-target functions since both pickers want the same source set.

## 0.1.158-dev (2026-05-08)
- Removed: `attack_push → attack_swing_left_diagonal` entry from `_kruber_axe_falchion_remap`. `attack_push` is in the target template's authored vocabulary (`dual_wield_hammer_sword_template`'s `action_one.push`) and plays natively on Kruber's mace+sword wield SM — remapping it to a strike was an unnecessary substitution. The remaining four entries (H1 charge+release, H2 release, down_left light) are direction-coherent and target events present in the closed vocabulary.
- Added: `character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md` — standardized 8-step procedure for fixing 3P animations on cross-character weapons. Codifies the **closed-vocabulary rule**: every remap target MUST appear in the `anim_event` set of the target body's wield-SM-matching template. Picking events outside that set is the recurring failure mode regardless of `Unit.has_animation_event` / `wt force3p exists=true` reports.
- Refactored: `_kruber_axe_falchion_remap` comment block now spells out the closed list and points at the playbook.

## 0.1.157-dev (2026-05-08)
- Added: `cwv_es_warpriest_hammer` (Warrior-Priest Hammer) — clone of Saltzpyre's `wh_1h_hammer` (Skullsplitter, `one_handed_hammer_priest_template`) enabled natively on all 4 Kruber careers. Right-hand mesh is the vanilla `wpn_wh_1h_hammer_01`; default skin shipped, then 8 cosmetic alternates.
- Added: 8 cosmetic illusion options on `cwv_es_warpriest_hammer` — the rescaled Kruber greathammer skins (`es_2h_hammer_skin_01/02/03/04/06` + runed/bogenhafen variants) at scale `{0.75, 0.75, 0.575}` and offset `{0, 0, -0.04}`. The 2H mesh in a 1H slot reads oversized — by design.
- Removed: 24 greathammer illusion entries previously registered on `es_1h_mace`, `es_mace_shield`, and `es_dual_wield_hammer_sword` (added v0.1.151). Per user direction, the rescaled-greathammer-on-mace look now lives only on the new dedicated `cwv_es_warpriest_hammer` variant rather than polluting Kruber's vanilla 1h-mace pickers.
- Fixed: dual maces cosmetic picker preview for `cwv_es_dual_maces` (Kruber) and `cwv_wh_dual_maces` (Saltzpyre). Added `item_type` on each def, registered `cwv_es_dual_maces_skins` / `cwv_wh_dual_maces_skins` in `_seed_targets` and `_item_type_to_skin_table`, and added both to `_force_display_unit` → `display_dual_hammers`. Same fix shape as v0.1.145 (cwv_es_dual_swords) and v0.1.152 (cwv_es_dual_axes); vanilla precedent is `weapon_skins_bless.lua:395` where DLC dual-hammer skins use the same rig.

## 0.1.156-dev (2026-05-08)
- Fixed: shortsword crash on heavy attack mid-sweep — `World.create_particles("fx/wpnfx_staff_spark_impact")` failed because the staff_spark FX package isn't loaded for empire-soldier wielders. The dagger's burning heavies hardcode `hit_effect = "staff_spark"` + `fire_hit` sound events at the sub-action level. v0.1.155 swapped the burning damage profiles but left these FX/sound fields untouched, so the engine still tried to play the fire visuals on hit. Fixed by adding `_SHORTSWORD_FX_SWAP` (Step 3 in the actions-loop pass): `staff_spark → melee_hit_sword_1h`, `fire_hit → slashing_hit` (both impact and armor variants), `fire_hit_armour → slashing_hit_armour`. Shortsword now reads as steel-on-target.

## 0.1.155-dev (2026-05-08)
- Added: `cwv_es_shortsword` `right_hand_scale = { 0.7, 0.7, 1.0 }` — Sienna's dagger model reads larger than a Reikland shortsword should; thinned on X/Y, length kept at native.
- Added: VMF setting widget `mace_sword_tweak` ("Mace and Sword Name and Cosmetic Tweak") in `_data.lua`, default ON, with description copy in `_localization.lua`. Applies to the VANILLA `es_dual_wield_hammer_sword` only — the CWV `cwv_es_sword_and_mace` variant is a separate weapon and is unaffected.
- Added: when the toggle is ON:
  - Vanilla mace+sword's display name is rewritten to "Cudgel and Short Sword" via the existing `mod:hook(_G, "Localize", ...)` (intercepts `es_dual_wield_hammer_sword_skin_01_name`).
  - Vanilla mace+sword's left-hand sword unit (`wpn_emp_sword_06_t1`) is scaled to `{0.7, 0.7, 1.0}` to match the standalone Shortsword variant. Right-hand mace stays native.
- Implementation: `_ES_MACE_SWORD_TWEAK_DEF` synthetic transform def is returned by `_resolve_cwv_def` when the lookup falls through to the `key == "es_dual_wield_hammer_sword"` check AND the toggle is on. Backend_id-prefix guard (`bid:sub(1,4) == "cwv_"`) ensures we don't accidentally apply to `cwv_es_sword_and_mace`, which shares the same base_weapon and would otherwise resolve via `item_data.key` per `feedback_cwv_backend_id_lookup.md`.
- Both checks (Localize override and transform resolution) read `mod:get("mace_sword_tweak")` at call time so toggling responds at runtime without a mod reload.

## 0.1.154-dev (2026-05-08)
- Fixed: shortsword crash on `heavy_attack_left` fire. v0.1.151 used `medium_slashing_linesman_fencer` as the burning-slam swap target — that name doesn't exist in `DamageProfileTemplates`, and `NetworkLookup.damage_profiles` is a strict-lookup table that crashifies on missing keys. Switched to `medium_slashing_linesman` (real, heavy slashing — closest non-burning analog by damage shape).
- Moved: `cwv_bw_shortsword` → `cwv_es_shortsword`. `character = "empire_soldier"`, `careers = _es_all_careers`. Sienna's dagger moveset on Kruber's empire-soldier 3P body is cross-character; if specific anim events don't read on his sub-graph, `_cross_access_action_remap[bw_dagger]` is the documented fix path.
- Updated: greathammer-on-1H illusion scale and grip. Z scale 0.5 → 0.65 (less aggressive shortening) and added `right_hand_offset = { 0, 0, -0.04 }` for grip alignment. All 24 entries.

## 0.1.153-dev (2026-05-07)
- Fixed: applied the dual-wield display rig fix to `cwv_es_sword_and_mace` (Sword and Mace, the inverse of Kruber's vanilla mace+sword). Added `item_type = "cwv_es_sword_and_mace"` on the def, registered `cwv_es_sword_and_mace_skins` in `_seed_targets` and `_item_type_to_skin_table`, and added the variant to `_force_display_unit` → `display_dual_weapons` (matching `dual_wield_hammer_sword.lua:1572` — vanilla Kruber mace+sword uses the same rig and ships a working cosmetic preview).
- Without `item_type` the variant inherited `es_dual_wield_hammer_sword`'s vanilla `skin_combination_table`, so the picker would have shown vanilla mace+sword skins. Vanilla skins set `right_hand_unit = mace` + `left_hand_unit = sword` — the OPPOSITE of this variant's intended sword-right + mace-left layout — so applying any vanilla illusion would have flipped the hands and erased the variant's visual identity. Curated table fixes that.

## 0.1.152-dev (2026-05-07)
- Added: 10 vanilla `wh_1h_axe` skins as cosmetic illusion options on `cwv_es_dual_axes` (Kruber's Imperial Dual Axes). Mirrors all of Saltzpyre's 1h axe skins — every skin in `ItemMasterList` with `matching_item_key = "wh_1h_axe"` is cloned into `cwv_es_dual_axes_<source_key>` with both hands set to the source mesh and registered in the new `cwv_es_dual_axes_skins` skin_combination_table.
- Added: `item_type = "cwv_es_dual_axes"` on the variant def and the matching `cwv_es_dual_axes_skins` entry in `_seed_targets` and `_item_type_to_skin_table`. Without `item_type` the variant inherited `dr_dual_wield_axes`'s skin_combination_table and would have shown Bardin's dual-axe vanilla skins in the picker (visually wrong family).
- Refactored: replaced the cwv_es_dual_swords-specific `if def.item_key == "cwv_es_dual_swords"` branch in `_register_variant_skins` with a `_force_display_unit` map keyed by `def.item_key`. New entries: `cwv_es_dual_swords` → `display_dual_weapons`, `cwv_es_dual_axes` → `display_dual_axes`. Pattern documented in `DEVELOPMENT.md` "Dual-wield variants — display rig requirements" and follows the same v0.1.145 fix shape (vanilla precedent: `dw_dual_axe_skin_01` at `weapon_skins.lua:2364` uses `display_dual_axes` with both hands set).

## 0.1.151-dev (2026-05-07)
- Added: greathammer illusion options for Kruber's 1H mace weapons. 8 source skins (`es_2h_hammer_skin_01/02/03/04/06` + runed/bogenhafen variants) registered as illusions on `es_1h_mace`, `es_mace_shield`, and `es_dual_wield_hammer_sword` — 24 entries total. Right-hand greathammer model is scaled to `{0.75, 0.75, 0.5}` so the 2H mesh fits the 1H slot.
- Added: `_register_custom_illusions` now supports `right_hand_unit_override` and `left_hand_unit_override` fields on illusion defs. Used to preserve the off-hand model when a cross-type illusion's source skin has only a right_hand_unit (greathammer → mace+shield keeps the shield, greathammer → mace+sword keeps the sword).
- Added: `_skin_transform_map` builder now also walks `_custom_illusions` and registers any entry with its own `right/left_hand_scale` or `_offset` fields. Lets illusion-applied scales fire through the existing transform-application hooks (`GearUtils.create_equipment`, `HeroPreviewer._spawn_item`, `MenuWorldPreviewer._spawn_item`, `LootItemUnitPreviewer.spawn_units`) without any new hook surface.
- Added: `cwv_es_sword_and_mace` ("Sword and Mace") — INVERSE of Kruber's `dual_wield_hammer_sword`. Sword in right hand (`wpn_emp_sword_02_t1`), mace in left (`wpn_emp_mace_02_t1`). Template clone (`sword_and_mace_template`) walks each sub-action and swaps damage_profile / hit_effect / impact_sound_event / no_damage_impact_sound_event by `weapon_action_hand`: right→slashing, left→blunt, both→swap left/right damage profile fields where they differ. Anims unchanged (still `to_dual_hammer_sword_es`).
- Added: `cwv_es_cudgel` ("Cudgel") — Kruber 1H mace stat clone (`cudgel_template` from `one_handed_hammer_template_1`), +20% attack speed, −15% power. Uses `wpn_emp_mace_04_t2` model from his mace+sword.
- Added: `cwv_bw_shortsword` ("Shortsword") — Sienna dagger moveset stat clone (`shortsword_template` from `one_handed_daggers_template_1`), −20% attack speed, +15% power. Fire DoT scrubbed: `dagger_burning_slam_fencer` → `medium_slashing_linesman_fencer`, `medium_burning_smiter_stab_H` → `medium_slashing_smiter_stab`, AoE/target slam fields removed (no non-burning slam-AoE analog exists for Sienna's body — heavy slam loses AoE component but main-target damage and visual remain). Uses `wpn_emp_sword_06_t1` (Kruber's mace+sword sword).
- Added: `_bw_all_careers` definition (4 Sienna careers).

## 0.1.150-dev (2026-05-07)
- Added: `_cross_access_action_remap[dr_dual_wield_axes]` for all 4 Kruber careers — 3 entries (`attack_swing_charge_diagonal` → `_charge_left`, `attack_swing_heavy_right` → `_heavy_right_diagonal`, `attack_swing_heavy` → `_heavy_left_diagonal`). Bardin's heavy_attack and heavy_attack_2 release events weren't authored on Kruber's `dual_hammer_sword` sub-graph and silently played nothing — these substitutes are. Charge directions selected so the wind-up matches the new release direction.
- Added: full "Animation: cross-access weapons (career-specific runtime remap)" section in `character_weapon_variants/DEVELOPMENT.md` covering the runtime-hook pattern, where it lives, the 5-step procedure for adding a new remap, what's not remapped (1P, husks, native wielders, cross-SM clips), common mistakes specific to this pattern, and a decision table mapping situation → animation pattern.

## 0.1.145-dev (2026-05-07) — user-confirmed working
- Fixed: `cwv_es_dual_swords` cosmetic illusion picker rendered only ONE sword (single-sword preview, regression introduced by v0.1.142's H4 crash-stop). Root cause: v0.1.142 gated the BackendUtils right→left mirror behind a `_in_loot_previewer_load` flag, which stopped the `j_leftweaponattach` crash but also stopped the picker from rendering the left sword. Per the H5 hypothesis in `J_LEFTWEAPONATTACH_INVESTIGATION.md`, vanilla `we_dual_sword_skin_01` (`weapon_skins.lua:5750`) sets `display_unit = "units/weapons/weapon_display/display_dual_weapons"` with both `left_hand_unit` and `right_hand_unit` populated — and the in-game vanilla elf-dual-sword cosmetic preview is a shipped feature that works. So `display_dual_weapons` DOES author `j_leftweaponattach`; the v0.1.131 finding that it didn't was an artifact of testing while the auto-generated default skin was still inheriting `display_1h_weapon` (a single-sword rig). Switched both the auto-generated `cwv_es_dual_swords_skin` and the 17 Kruber 1h-sword illusion clones to `display_dual_weapons` and restored `left_hand_unit = right_hand_unit` on every entry. Picker and Athanor forge previews now show two identical Kruber swords.
- Removed: the `_in_loot_previewer_load` thread-local flag and its `LootItemUnitPreviewer._load_item_units` wrapper hook (obsolete now that the mirror itself is gone).
- Removed: the right→left mirror block in the `BackendUtils.get_item_units` hook. Vanilla resolves `result.left_hand_unit = skin_template.left_hand_unit` directly from the skin entry; our mirror was working around an absent field that we now populate at registration time.
- Kept: `_kruber_1h_dual_skin_keys` registry as an introspection marker (no runtime consumer remaining; left in place in case a future hook needs to filter on cwv_es_dual_swords skin lineage). Crash GUID `01b5fbdd-31ff-4052-97ce-3f70bcc0295a`.

## 0.1.143-dev (2026-05-07)
- Reverted: Black Guard Blade mesh back to `wpn_empire_2h_sword_03_t2` per user — they did not ask me to change the model. v0.1.134's switch to `wpn_empire_2h_sword_05_t1` is undone. The mesh now matches what the user had set before my edit. The Knights-of-Morr description from v0.1.134 is kept (that part was requested).
- Reverted the dropped/restored vanilla illusion clones to match the pre-v0.1.134 set: `cwv_il_es_06` is back in dropped state (its mesh `wpn_greatsword` was kept dropped as a conservative carryover); `cwv_il_wh_05` is restored. `cwv_il_es_04` and `cwv_il_es_05` remain dropped (still dupe Nordland and Recruit by mesh).

## 0.1.140-dev (2026-05-07)
- Added: cross-character per-action 3P anim event remap system. Hooks `Unit.animation_event` and rewrites events for cross-access weapons — career-keyed via `_cross_access_action_remap[item_key][career_name]`. Native wielders bypass via gate 3 (career not in remap), so Saltzpyre's native axe+falchion is unaffected by Kruber's per-action overrides.
- Reverted: per-action `anim_event_3p` mutation on `dual_wield_axe_falchion_template` (v0.1.133–v0.1.139) — was affecting Saltzpyre's native template too. The runtime-hook approach above is the correct architecture for Kruber-specific remaps on a shared vanilla template.
- Wield tracker: `mod:hook_safe("SimpleInventoryExtension", "wield", ...)` updates `_cross_access_local_weapon_key` and `_cross_access_local_career` on melee swap so the per-event lookup is cheap.

## 0.1.134-dev (2026-05-07)
- Fixed: Black Guard Blade (`cwv_es_longsword_blackguard`) was rendering with `wpn_empire_2h_sword_03_t2` — the **same mesh** as the Nordland Claymore — so the two looked identical in the picker. Switched to `wpn_empire_2h_sword_05_t1` (exotic-tier ornate Empire greatsword), visually distinct from Recruit (04_t1) and Nordland (03_t2), and a fitting silhouette for a Knights-of-Morr brotherhood blade.
- Rewrote: Black Guard Blade description with proper Knights-of-Morr lore (the user clarified the variant is inspired by them, not the Helmgart watch). One sentence (down from two): "Borne by the Knights of Morr, the black-mantled brotherhood of the death-god whose vigil keeps Stirland's tombs sealed against the necromancers of Sylvania." References Morr (death-god), the order's black livery, Stirland (their primary chapter, bordering Sylvania), and their core mandate (containing the restless dead and combatting necromancy).
- Reshuffled: vanilla illusion clones to follow the new mesh assignments. `cwv_il_es_06` (mesh `wpn_greatsword`) RESTORED — no longer a duplicate of any curated variant since Black Guard moved off that mesh. `cwv_il_wh_05` (mesh `wpn_empire_2h_sword_05_t1`) DROPPED — now duplicates Black Guard's new mesh. `cwv_il_es_04` and `cwv_il_es_05` remain dropped (still dupe Nordland / Recruit). Comment in `_custom_illusions` rewritten to spell out the curated mesh assignments so the duplicate audit is one-glance.

## 0.1.127-dev (2026-05-07)
- Fixed: cwv scale / grip-offset rules were not applying to the cosmetic picker preview pane (the middle 3D viewport in the illusion menu). The user noticed the previews were "too large" and remembered cosmetics_tweaker had to do an "extra step" for the same issue with its bret-thinning hook. Root cause: CWV's `LootItemUnitPreviewer.spawn_units` hook used `mod:hook_safe` and read `self._spawned_units`, but vanilla `_spawn_items` (`loot_item_unit_previewer.lua:522`/`532`) calls `self:spawn_units(units_to_spawn)` and only assigns `self._spawned_units = units` AFTER `spawn_units` returns — so the hook_safe post-callback fires BEFORE the assignment and `self._spawned_units` is nil. The scale logic short-circuited at `if not spawned then return end`. Switched to `mod:hook` (full wrapper), read `units` from the wrapped call's return value, transform, and return — matches the cosmetics_tweaker pattern documented in its v0.7.x bret-thinning fix. The hook now actually applies cwv scale / offset to picker previews.
- Removed: `cwv_il_es_04`, `cwv_il_es_05`, `cwv_il_es_06` illusion clones. Each shared its mesh with one of our curated cwv variants (Nordland / Recruit / pre-v0.1.114 Black Guard) and rendered as a visual duplicate in the picker. User confirmed: "Sergeant's Greatsword" (the in-game vanilla name for `es_2h_sword_skin_05`, mesh `wpn_empire_2h_sword_04_t1`) was visually identical to the curated Recruit Longsword. The runed variants (`cwv_il_es_04_runed_01` / `_runed_02`) are kept since their rune detailing makes them visually distinct from the bare mesh.

## 0.1.113-dev (2026-05-07)
- Added: 17 vanilla 2h-sword skins as illusion options on the cwv Imperial Longsword (`cwv_imperial_longsword_skins`). Mirrors all of Kruber's `es_2h_sword_skin_*` (9 skins: 01–06 plus runed_01/runed_02 variants) and Saltzpyre's `wh_2h_sword_skin_*` (8 skins: 01–05 plus runed_01/runed_02 variants) — bogenhafen variants included. Picker now shows 20 options (3 cwv-curated + 17 cross-character vanilla). Initial display_name / description on each clone falls through to the source vanilla skin's localization keys; user will rename them as they review.
- Implemented via the existing `_register_custom_illusions` pipeline. Each entry uses `matching_weapon = "es_bastard_sword"` so the vanilla template lookup in `_apply_skin_to_item` resolves correctly to `bastard_sword_template` (the Imperial Longsword's moveset). New `target_combo` field on illusion defs explicitly directs the skin into a specific combo table (`"cwv_imperial_longsword_skins"`) — without it, `_register_custom_illusions` would resolve the combo via `matching_weapon`'s `skin_combination_table` (`es_bastard_sword_skins`) and the skin would land in the wrong picker. Skin keys are `cwv_il_es_<n>` / `cwv_il_wh_<n>` so they pass the existing v0.1.105 picker filter (`^cwv_` prefix). can_wield = Empire careers (the Imperial Longsword's wielders).

## 0.1.107-dev (2026-05-07)
- Renamed: Imperial Longsword family per user.
  - `cwv_es_longsword_veteran`: "Halfling Splitter" → **"Nordland Claymore"**.
  - `cwv_es_longsword_helmgart`: "Helmgart Watchsword" → **"Black Guard Blade"**.
- Rewrote: descriptions for all three Imperial Longsword variants in Warhammer-Fantasy-flavoured prose. Recruit Longsword is now standard Reikland state-regiment issue from Altdorf smithies. Nordland Claymore is the seal-hide-gripped pattern carried by Nordland coastal regiments fighting Norscan reavers (Salzenmund / Sea of Claws). Black Guard Blade is consecrated steel of the Helmgart watch holding the western pass against Reikwald beastherds.
- Updated stale comment in `_type_transforms` to use the new family names instead of "Halfling Splitter, Helmgart Watchsword".

## 0.1.105-dev (2026-05-07)
- Fixed: the Bretonian Longsword illusion appeared as an extra option in the cwv Imperial Longsword cosmetic picker. Root cause: vanilla `HeroWindowItemCustomization._setup_illusions` (`hero_window_item_customization.lua:1586`) appends `WeaponSkins.default_skins[item_key]` to the picker after iterating the item's `skin_combination_table`. CWV items inherit `entry.key = "es_bastard_sword"` from their clone (per `feedback_cwv_clone_name_clobber.md`); `item.ItemId` resolves through that key, and `WeaponSkins.default_skins.es_bastard_sword = "es_bastard_sword_skin_01"` (`weapon_skins_lake.lua:251`). Picker added the Bretonian default as a 4th widget alongside our 3 cwv skins. Added `_setup_illusions` post-hook that filters `self._illusion_widgets` for cwv items: keeps only widgets whose `skin_key` starts with `cwv_`, then recomputes the centered horizontal layout (mirrors vanilla's loop at `:1611-1618`). Cwv detection is via `backend_id` matching `^cwv_.+_001$` with a fallback to `item_data.cwv_variant`.

## 0.1.103-dev (2026-05-07)
- Fixed: v0.1.99's display_unit fix didn't actually work — log from user's 00:25 test confirmed every cwv skin registered with `display_unit=nil` and the previewer still warned `[LootItemUnitPreviewer] Couldn't find any display unit for item "cwv_es_longsword_skin"`. v0.1.99 read `base.display_unit` (i.e. `ItemMasterList[def.base_weapon].display_unit`) but vanilla weapon entries DON'T carry that field on the weapon row — only on the **weapon_skin** rows (e.g. `ItemMasterList.es_bastard_sword_skin_01.display_unit = "units/weapons/weapon_display/display_2h_swords"`, `item_master_list_lake.lua:246`). v0.1.103 now scans `ItemMasterList` for any vanilla weapon_skin entry whose `matching_item_key == def.base_weapon` and copies its `display_unit` onto our cwv skin's WeaponSkins.skins entry AND its ItemMasterList entry. Per-variant `def.display_unit` overrides if explicitly set.

## 0.1.100-dev (2026-05-07)
- Fixed (THE javelin behavior fix, after a long debugging chain): the projectile system was reading the BASE `javelin_template` at runtime, not our cloned `tuskgor_javelin_template`. Every stat / timing / impact_data override on the clone was dead code in-game — the vanilla javelin's `link = true + wall_nail = true` impact_data was what actually controlled the stick mechanic, which is why the engine took `_link_projectile` (the static-decoration attach) instead of `_spawn_linked_pickup_projectile` (the pickup-spawn path with our rotation cleanup). Confirmed via diagnostic trace in v0.1.96: every throw logged `tmpl=javelin_template` regardless of cwv variant.
- Root cause: `PlayerProjectileUnitExtension.init` reads `ItemMasterList[item_name]` where `item_name = "we_javelin"` (BASE key — cwv items return their base key for `item_data.name`/`.key` per memory `feedback_cwv_backend_id_lookup.md`). The base entry has no `backend_id` field, and its `template` is `"javelin_template"`. So the projectile got vanilla impact_data even when the equipped weapon was our `cwv_es_javelin`.
- Fix: `mod:hook_safe("PlayerProjectileUnitExtension", "init", ...)` runs AFTER vanilla init, looks up the projectile's owner via `extension_init_data.owner_unit`, reads `inventory_extension:get_slot_data("slot_ranged").id` (where the cwv backend_id IS preserved), and if it matches `^cwv_.+_javelin_001$`, swaps `self._current_action`, `self._impact_data`, `self.projectile_info`, and `self._impact_damage_profile_id` to point at our cloned template's `throw_charged` sub-action. The projectile now reads OUR fields for the rest of its lifecycle.
- Also fixed (sibling bug exposed during this investigation): two separate `mod:hook_safe` registrations on `PlayerProjectileUnitExtension.init` (the diagnostic logger added in v0.1.96 + the post-fix added in v0.1.98) silently never fired. **VMF's `hook_safe` does not chain multiple handlers on the same method — the second registration shadows the first.** Symptom: hooks logged "Hooking 'init'" twice in mod load output, but neither hook's body executed at runtime. v0.1.100 collapses both into a single hook_safe handler so the diagnostic trace and the swap logic share one callback.
- Carry-over implication: all the impact_data / projectile_speed / action_speed / damage / ammo overrides we shipped over the past 30+ versions on `tuskgor_javelin_template` apply NOW for the first time. Expect a noticeable behavior shift the moment v0.1.100 loads — slower wind-up, slower projectile, harder hit, finite 10-shot stack, link_pickup-style stick + pickup. If the user has been tuning around perceived behavior since v0.1.70, those tunings need re-validation against the post-v0.1.100 reality.

## 0.1.99-dev (2026-05-06)
- Fixed: cwv illusion options in the cosmetic picker (the middle 3D preview pane) rendered as INVISIBLE on hover, with one option falling back to a Bretonian Longsword model. Vanilla `LootItemUnitPreviewer._spawn_link_unit` (`loot_item_unit_previewer.lua:467`/`472`) reads `display_unit` from the item_data, then from `WeaponSkins.skins[skin].display_unit`, and bails with a warning if both are nil. The "link unit" is the spinning pivot every weapon unit attaches to in the picker preview pane — when it fails to spawn, the weapon units have nothing to attach to and the pane is empty. Vanilla weapon entries declare `display_unit` in their equipment files (e.g. `display_2h_swords` for greatswords), but our mod-injected weapon_skin entries didn't. Now inherits `display_unit` from the cloned base weapon (`base.display_unit`) and writes it onto BOTH the `WeaponSkins.skins` entry AND the `ItemMasterList` weapon_skin entry.
- Fixed: secondary issue exposed by the same investigation. Vanilla `parse_item_master_list` (`item_master_list.lua:111-112`) sets `item.key = key; item.name = key` on every entry at boot. Our weapon_skin entries are added AFTER boot via `_register_variant_skins`, so they didn't have `.key` / `.name` set — and `_load_item_units` line 254 does `item_key = item_data.key or item.key` which fell through to nil, then `ItemMasterList[nil]` returned nil silently and the resolution chain failed. Now sets `key = skin_key` and `name = skin_key` explicitly on the weapon_skin ItemMasterList entry.
- The "Bretonian Longsword model" in the picker was likely the visual default fallback for the previewer when our skin failed to resolve through the normal path — same bug, different symptom; fixed by the display_unit + key/name additions above.

## 0.1.97-dev (2026-05-06)
- Tuned: Imperial Longsword Z grip offset `-0.075` → `-0.065` per user.

## 0.1.95-dev (2026-05-06)
- Fixed: applying the Helmgart Watchsword illusion (or any other `skin_only` variant's illusion) onto a sibling cwv variant crashed with `Requested template for item cwv_es_longsword_helmgart which does not exist` in `foundation/scripts/util/error.lua:26`. v0.1.91 set `matching_item_key = def.item_key` on every `cwv_*_skin` ItemMasterList entry. For non-skin_only variants that's fine (item_key is mirrored into ItemMasterList by `_auto_register_all`). But `skin_only = true` variants are deliberately NOT mirrored — they exist only to provide the illusion, never as a wieldable inventory item. Vanilla `_apply_skin_to_item` does `ItemHelper.get_template_by_item_name(matching_item_key)` and crashes when the key resolves to a non-existent ItemMasterList entry. Now uses `def.base_weapon` as the matching_item_key — the vanilla weapon every cwv variant clones from, always present in ItemMasterList with a real template (e.g. `bastard_sword_template`). GUID ca46d7b2-65b8-41b2-b16b-d71b6dcb9be6.

## 0.1.93-dev (2026-05-06)
- Fixed: default-rarity CWV blacksmith templates (`cwv_es_longsword` Recruit Longsword, `cwv_es_axe_shield` Axe and Shield) were rendering the BASE weapon's mesh in the inventory character preview after v0.1.87 — Bretonian Longsword instead of Imperial, Bardin axe-and-shield instead of the cwv Empire axe + Empire shield. Root cause: vanilla `BackendUtils.get_item_units` reads `item_data.right_hand_unit` directly from whatever `item_data` was passed in. CWV entries inherit `entry.name` and `entry.key` from the base weapon (per `feedback_cwv_clone_name_clobber.md`), so an upstream lookup via `ItemMasterList[item.name]` returns the BASE entry — whose `right_hand_unit` is the base mesh. Pre-0.1.87 the pre-applied skin on `mod_data.CustomData.skin` masked this by forcing `BackendUtils` to use the skin's `right_hand_unit` (= the cwv mesh). 0.1.87 removed the pre-apply for default-rarity items so the forge would treat them as unlocked, which exposed the latent base-mesh-fallback. Fix: hook `BackendUtils.get_item_units`. When `backend_id` matches `cwv_<key>_001` and no skin ended up applied (`result.skin` nil/empty), force `result.right_hand_unit` and `result.left_hand_unit` to the cwv def's overrides. When a skin IS applied (curated exotic / unique cwv weapons OR a user-selected illusion), we leave the skin's units in place so user choice still wins. Also covers the grip-offset path because the model rendering and the `_cwv_spawn_item_post` transform both go through this resolution.

## 0.1.91-dev (2026-05-06)
- Fixed: opening the inventory illusion picker on a CWV variant (newly possible after the v0.1.87 default-rarity-skin gate unlocked the forge) crashed with `attempt to index local 'item_data' (a nil value)` in `hero_window_item_customization.lua`. Vanilla `_apply_skin_to_item` does `ItemMasterList[skin_key]` on the selected illusion's key; CWV registered each `cwv_*_skin` in `WeaponSkins.skins` and the skin_combinations table but never wrote the entry into `ItemMasterList`. Pre-0.1.87 this path was never reached because the item was treated as locked. `_register_variant_skins` now also writes a complete `weapon_skin` entry into `ItemMasterList` (item_type, slot_type, matching_item_key = the cwv variant, rarity, display fields, hand units, can_wield, hud_icon, inventory_icon, information_text, template = nil) — same shape `cosmetics_tweaker._register_custom_illusions` uses. Also mirrors the skin key into `NetworkLookup.item_names` since vanilla weapon-skin RPCs and equipment-grid widgets resolve through that table (parallel to v0.1.24's weapon-item registration fix). GUID b25c1fe3-8141-4f16-ac8c-62d8d2e8d5c3.

## 0.1.88-dev (2026-05-06)
- Doc-only: clarified the in-code comment and 0.1.87 changelog entry to frame the cwv_es_longsword Imperial model as its default model (set on `entry.right_hand_unit`), not as an illusion. The previous wording implied the player had a "Recruit Longsword illusion" they could re-apply if missing — that's the wrong mental model. The Imperial mesh IS the Recruit Longsword's base look; the skin entry exists only so OTHER Imperial Longsword variants can apply this look as an illusion if they want.

## 0.1.87-dev (2026-05-06)
- Fixed: `cwv_es_longsword` (Recruit Longsword, the `rarity = "default"` / `power_level = 5` blacksmith template) was showing up in the forge as a locked-illusion variant instead of an unlocked default-tier item. Root cause: `_build_entry` unconditionally wrote `mod_data.CustomData.skin = "<item_key>_skin"` for every CWV variant. That's correct for exotic / unique curated weapons (Halfling Splitter, Helmgart Watchsword) — those are designed as fixed-illusion curated looks. But the Recruit Longsword's Imperial model (`wpn_empire_2h_sword_04_t1`) is its **default model** — set on `entry.right_hand_unit`, picked deliberately for this weapon. It is not an illusion applied on top of the Bretonian base. The skin pre-apply was a redundant indirection that also broke the forge: vanilla blacksmith templates carry `mod_data.CustomData.skin = nil`, and that's the state required for the forge to treat the item as unlocked. Now gated on `def.rarity ~= "default"`; default-rarity entries leave the skin field nil and present to the forge identically to a vanilla blacksmith template. The Imperial model still renders by default because `BackendUtils.get_item_units` falls back to `item_data.right_hand_unit` when no skin is set. The `cwv_es_longsword_skin` entry is still registered as a side-effect — other Imperial Longsword variants can apply the Recruit's look via the cosmetic menu if desired — but the Recruit itself doesn't pre-apply it because its base model already IS that look.

## 0.1.86-dev (2026-05-06)
- Tuned: Imperial Longsword Z grip offset `-0.75` → `-0.075` per user (typo correction — 0.75 was 10x too far).

## 0.1.85-dev (2026-05-06)
- Tuned: Imperial Longsword Z grip offset `-0.1` → `-0.75` per user.

## 0.1.84-dev (2026-05-06) — user-confirmed working in v0.1.85
- Fixed: Imperial Longsword grip offset (and any other CWV per-variant scale or grip offset) was never visible on the inventory character preview. Diagnostic added in 0.1.83 confirmed the cause: `_cwv_spawn_item_post` was looking up `equip_units[target_slot_id]` with a STRING slot_type ("melee"/"ranged"), but `_equipment_units` is keyed by NUMERIC `slot_index`. Result: `slot` was always nil and the apply path was skipped. Same bridge bug cosmetics_tweaker hit and fixed in 0.7.88. Now reads `info.spawn_data[1].slot_index` (vanilla `equip_item` populates that field per-spawn at `world_hero_previewer.lua:704/728`) to bridge the two keying conventions. Verified by user — inventory character preview now shows the same scaled-and-offset model the in-game body shows. The dropped fallback loop ("match by item_name") used the STRING slot_type as iterator key against the numeric-keyed equip_units; preserved as a "don't reintroduce" warning in the in-code comment and `feedback_preview_slot_keying.md`.
- Stripped: the diagnostic logs added in 0.1.83 now that the data did its job.
- Diagnostic: javelin stick-rotation hooks expanded — v0.1.82 hook on `PickupSystem.rpc_spawn_linked_pickup` showed zero fires in the log despite user-confirmed wall sticking, so the throw must be taking a different code path. Added trace hooks on `PlayerProjectileUnitExtension._spawn_linked_pickup_projectile` (Path A entry) AND `PlayerProjectileUnitExtension._spawn_pickup_projectile` (Path B entry, fires when allow_link=false). Added correction hook on `ProjectileSystem.rpc_spawn_pickup_projectile` (NOTE: different class than PickupSystem, different RPC, different rotation logic — random_angle around bounce direction). Added universal-fallback hook on `PickupUnitExtension.extensions_ready` to set rotation post-spawn regardless of which path got us there. All hooks log to `[cwv stick]` / `[cwv stick:trace]` so the next throw test will reveal which path is actually taken.
- Refactored rotation cleanup to shared helpers `_is_our_pickup(name)` and `_clean_horizontal_rotation(rot)` — DRYs up the four call sites.
- Tuned: Imperial Longsword Z grip offset settled at `-0.1` (user-confirmed). `-0.2` was too high; the negative direction is correct for this Empire greatsword family despite the general "+Z = grip lower" rule in `feedback_grip_offset_sign.md` — per-model authoring axes can flip it.

## 0.1.83-dev (2026-05-06)
- Tuned: Imperial Longsword grip offset flipped from `+0.1` to `-0.2` on Z. User-tested +0.1 went the wrong visual direction for the Empire greatsword model family; per-model authoring axes can flip the convention documented in `feedback_grip_offset_sign.md` ("+Z lowers grip"), so we trust visual confirmation over the rule. Doubled magnitude since +0.1 was barely visible.
- Diagnostic: added detailed logging to `_apply_offset` (logs reason on every skip-branch — invalid unit / not alive / dedupe block) and to `_cwv_spawn_item_post` (logs `slot.right` / `slot.left` validity and the resolved offset values per call). Reason: in v0.1.81 the in-game body shows the offset visibly but the inventory character preview does not, even though `_cwv_spawn_item_post` runs and logs "Preview transform"; need to see whether the preview path's `_apply_offset` call is being deduped, hitting nil units, or resolving nil offset. Once data tells us which, the next pass converts it to a fix and removes the diagnostic noise.

## 0.1.82-dev (2026-05-06)
- Fixed (probably): the v0.1.81 rotation hook on `ProjectileLinkerSystem.link_pickup` was effectively dead code for wall-sticks. Confirmed by re-reading `pickup_system.lua:1441-1446`: `_spawn_pickup` runs FIRST and applies `link_rotation` to the unit's world transform; `link_pickup` only re-applies rotation when the hit_unit has a `projectile_linker_system` extension (typical of enemy hit-zones, atypical of level walls). For wall stick the engine takes the else branch and our hook's modified `link_rotation` parameter is discarded.
- Moved hook earlier: `PickupSystem.rpc_spawn_linked_pickup` runs server-side BEFORE `_spawn_pickup`, with `link_rotation` as a writable parameter. Modifying it here propagates through the spawn AND through the subsequent `rpc_link_pickup` fan-out to clients.
- Upgraded rotation correction from "strip random_roll only" to "horizontal projection + clean rebuild": project the rotated forward onto the world horizontal plane (Stingray xy plane, since z is vertical), normalize, and rebuild as `Quaternion.look(horizontal, Vector3.up())`. This wipes both random_pitch (30°-60° around unit-left axis) AND random_roll (±18° around unit-forward axis). Trade-off: floor/ceiling sticks would point horizontally instead of into-the-surface. Acceptable since vertical walls are the common case.
- Instrumented: every hook fire on our two pickup names logs the input rotation's forward/right/up vectors AND the output rotation's, via `mod:info` to console.log. Tagged `[cwv stick]`. Lets us see in the log whether the hook fires AND whether the math produces the expected correction. Search the log for `[cwv stick]` after testing.

## 0.1.81-dev (2026-05-06)
- Fixed: Tuskgor Javelin sticking in surfaces at axe-style random tilt instead of pointing-into-wall like a thrown spear should. Root cause is in the engine's `PlayerProjectileUnitExtension._spawn_linked_pickup_projectile` (`player_projectile_unit_extension.lua:1346-1352`): it deliberately multiplies the directional `link_rotation` by `Quaternion(Vector3.forward(), random_roll ±18°)` and `Quaternion(Vector3.left(), random_pitch 30°-60°)` to give thrown weapons axe-style organic variety. That randomness reads as "tumbled into the wall" on a long pointed weapon — consistent with the user's observation that our javelins behave "like Bardin's throwing axes".
- Hooked `ProjectileLinkerSystem.link_pickup` (the function called by both the local spawn and `rpc_link_pickup`, so this covers host AND clients without two hooks). For our two pickup names only (`cwv_tuskgor_javelin_pickup` / `cwv_tuskgor_javelin_link_pickup`), rebuild `link_rotation` as `Quaternion.look(Quaternion.forward(link_rotation), Vector3.up())`. This preserves the engine's intended directional aim (the `link_direction = blend of incoming velocity + reflected hit_normal`) but wipes the random_roll cleanly. Random_pitch is partially baked into the forward vector and persists; if the residual reads wrong, a follow-up could project forward onto the horizontal plane (loses correct floor/ceiling stick orientation in exchange).
- Gated on `pickup_name` match — vanilla throwing axes intentionally want the random tilt, so the hook is a no-op for any pickup that isn't ours.

## 0.1.80-dev (2026-05-06)
- Tuned: Imperial Longsword grip offset switched from X axis (`{-0.1, 0, 0}`, lateral) to Z axis (`{0, 0, 0.1}`, along blade). Per `feedback_grip_offset_sign.md`, `+Z` lowers grip toward the hilt — that's the documented axis for the "hand on blade / grip too high" symptom. The earlier X attempt just shifted the unit sideways relative to the hand bone. Type-level entry — applies to all three Imperial Longsword variants.

## 0.1.79-dev (2026-05-05)
- Added: `mod:echo` on load so the version is visible in the in-game chat (matches cosmetics_tweaker's pattern). Previously only printed to console.log via `mod:info`, so confirming whether the latest bundle had loaded required a log dump.

## 0.1.78-dev (2026-05-05)
- Added: type-level scale/grip transform layer (`_type_transforms[item_type]`). The mod creates new conceptual weapon types (each `cwv_*` `item_type`) and a single tune now cascades to every variant of that type — no more duplicating `right_hand_scale` / `right_hand_offset` per model. Per-variant fields on a def still take precedence as a model-specific override (e.g. when a variant uses a different mesh family with different axis conventions).
- Resolution order at apply time: `def.<field>` → `_type_transforms[def.item_type].<field>` → nil. Implemented via `_resolve_field(def, field)` and used at all four transform-application sites (GearUtils, HeroPreviewer/MenuWorldPreviewer `_cwv_spawn_item_post`, LootItemUnitPreviewer). The `_transform_map` registration loop also goes through `_resolve_field` so a variant with no per-variant transform still gets registered when its type contributes one.
- Migrated: Imperial Longsword tune (introduced as three duplicated entries in 0.1.74–0.1.77) now lives at `_type_transforms.cwv_imperial_longsword = { right_hand_scale = {1.0, 0.8, 0.9}, right_hand_offset = {-0.1, 0, 0} }`. Stripped the duplicated fields from the three `cwv_es_longsword*` defs; each now carries a one-line comment pointing at the type entry. Helmgart Watchsword (which uses `wpn_greatsword`, a different model from the Empire 2h_sword family) inherits the type tune today; if its axis convention reads wrong, override at the variant level.

## 0.1.77-dev (2026-05-05)
- Tuned: `cwv_es_longsword_helmgart` (Helmgart Watchsword) — applied the same scale `{1.0, 0.8, 0.9}` and grip offset `{-0.1, 0, 0}` as the other two Imperial Longsword variants. Different model (`wpn_greatsword` vs the Empire greatsword family), so the axis convention may differ; if width/length read wrong on the Helmgart specifically, that entry is the place to deviate. The "Imperial Longsword" tune is conceptually a single family-wide treatment, applied to all three variants (Recruit / Halfling Splitter / Helmgart) regardless of underlying model.

## 0.1.76-dev (2026-05-05)
- Tuned: `cwv_es_longsword_veteran` (Halfling Splitter) — applied the same scale `{1.0, 0.8, 0.9}` and grip offset `{-0.1, 0, 0}` from v0.1.74-dev's Recruit Longsword tune. Same Empire greatsword family (03_t2 vs Recruit's 04_t1), same wide-axis (Y) / length-axis (Z) convention. Confirmed via in-game console log this is the variant the user has been testing on (the Recruit had been correct since 0.1.74 but invisible because they were equipping the exotic).

## 0.1.75-dev (2026-05-05)
- Added: `cwv_probe_unit <unit_path>` and `cwv_despawn_probes` console commands — diagnostic tooling for the Tuskgor Javelin pickup investigation. Spawns a Stingray unit at the player's feet (1.5m forward, 1m up) and dumps its asset-level properties to mod:info: actor count, per-actor name + static/kinematic/dynamic flags + collision_filter, bounding box, and runtime extension presence (pickup_system / outline_system / interactable_system). Persists until `cwv_despawn_probes` is called or the level changes.
- Purpose: Experiments A and B from the pickup-asset investigation plan. Run on three units to compare known-good vs candidate vs current-workaround:
  - `units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01_3p` (boar spear held — does it have any pickup-suitable actors?)
  - `units/weapons/player/wpn_dw_thrown_axe_01_t1/pup_dw_thrown_axe_01_t1` (known-good pickup — baseline)
  - `units/weapons/player/wpn_we_javelin_01/prj_we_javelin_01_3ps` (current workaround — what makes this one work?)
  - `units/weapons/player/spear_projectile/spear_3ps` (existing generic spear — visual audit, could substitute for boar spear)
- Decision matrix: if boar spear has actors comparable to the throwing axe pup, **H1 falsified** and we use the boar spear directly with just a rotation fix. If it has zero / non-pickup actors, proceed to parent-child unit-linking experiment (D in the plan). If `spear_3ps` is visually boar-spear-like, swap `_TJ_PICKUP_UNIT` to it as a one-line fix.

## 0.1.74-dev (2026-05-05)
- Tuned: `cwv_es_longsword` (Recruit Longsword) model proportions and grip:
  - `right_hand_scale = { 1.0, 0.8, 0.9 }` — Y trims 20% off width (Imperial greatsword's wide axis is Y, distinct from the Bretonian whose width is X — that's why this doesn't conflict with cosmetics_tweaker's `_breton_sword_thiccc` factor `{0.65, 1, 1}` on `wpn_emp_gk_sword_*`); Z trims 10% off blade length.
  - `right_hand_offset = { -0.1, 0, 0 }` — lateral X nudge so the hand sits on the hilt after the Y-thinning, instead of riding the blade. Sign per `feedback_grip_offset_sign.md`.
  - Veteran (`cwv_es_longsword_veteran`) and Helmgart (`cwv_es_longsword_helmgart`) variants left at `{1, 1, 1}` for now — different model paths (`wpn_empire_2h_sword_03_t2` and `wpn_greatsword`) so they may need their own tuning.

## 0.1.73-dev (2026-05-05)
- Fixed: Tuskgor Javelin pickups not pickup-able (no F-prompt, no ammo refill on interaction) AND stuck at 90° from expected orientation. Both root-caused to using the held boar spear `_3p` mesh as the pickup `unit_name`. Two compounding asset-level problems:
  - **No physics on the held mesh** — held weapon meshes attach to a hand bone and never need their own collision/physics. Pickups need physics so the player's interactor overlap query can find them and surface them as F-prompt-able. Without physics, pickup is invisible to the interaction system.
  - **Hand-attachment local axes** — the held mesh's local `+Y` is the spear tip; the engine's pickup spawn computes `link_rotation = Quaternion.look(link_direction, Vector3.up())` assuming the unit's `+Z` is the tip. Result: 90° rotation off.
- Decoupled in-flight projectile from pickup unit:
  - **In-flight unit** (`_TJ_BOAR_SPEAR_UNIT`): unchanged — `wpn_emp_boar_spear_01_3p`. The boar spear stays correct visually while flying because the in-flight render path doesn't go through the pickup spawn / interaction system.
  - **Pickup unit** (new `_TJ_PICKUP_UNIT`): swapped to `prj_we_javelin_01_3ps` — the elf javelin's purpose-built projectile/pickup mesh. Has physics + correct orientation + already in `NetworkLookup.husks` via the woods DLC. Both `cwv_tuskgor_javelin_pickup` and `_link_pickup` now use this unit.
- Cosmetic compromise: the **stuck/dropped** pickup reads as a slim elf javelin instead of a boar spear. Functional refill (+1 ammo on F) and proper orientation. Boar spear visual stays in-flight. If a real `prj_emp_boar_spear_*_3ps` unit ever gets authored, swap `_TJ_PICKUP_UNIT` to it.

## 0.1.72-dev (2026-05-05)
- Fixed: crash on first thrown Tuskgor Javelin: `Table husks does not contain key: units/weapons/player/wpn_emp_boar_spear_01/wpn_emp_boar_spear_01_3p`. The non-link pickup spawn path (`PlayerProjectileUnitExtension._spawn_pickup_projectile`, `player_projectile_unit_extension.lua:1382`) looks up `NetworkLookup.husks[pickup_unit_name]` before sending the spawn RPC, and the boar spear's `_3p` unit was never registered as husk-spawnable. Vanilla pickup units (e.g. throwing axe `pup_*` and `prj_*_3ps`) get added to `NetworkLookup.husks` via per-DLC `husk_lookup` tables (`anvil_common_settings.lua:8-18`); the boar spear only got the held _3p declaration in `anvil_equipment_settings.lua`'s `player_units` list, which doesn't feed husks. Now `_register_tuskgor_javelin_assets` rawset-injects the unit name into both `NetworkLookup.husks[idx]` and `NetworkLookup.husks[name]` before any throw can reach the spawn path.

## 0.1.71-dev (2026-05-05)
- Fixed: Tuskgor Javelin projectile now uses the boar spear mesh (was: slim elf javelin). Registered `ProjectileUnits.cwv_tuskgor_javelin` pointing at `wpn_emp_boar_spear_01_3p` (the held 3P unit — anvil DLC ships no `prj_*_3ps` projectile variant for the boar spear). Both javelin variant defs now set `projectile_units_template = "cwv_tuskgor_javelin"`. NetworkLookup.projectile_units injection added.
- Fixed: stuck javelins are now actually pickup-able. The 0.1.70 attempt set `link_pickup = true` on the throw action's impact_data, but `we_javelin` ItemMasterList has no `pickup_template_name` / `link_pickup_template_name` (vanilla javelin auto-recalls instead) so the skin entry mirrored nil for both — no pickup spawned. Now registers two custom pickup templates at runtime in `_register_tuskgor_javelin_assets`:
  - `Pickups.ammo.cwv_tuskgor_javelin_pickup` — for un-stuck ground spawns
  - `Pickups.ammo.cwv_tuskgor_javelin_link_pickup` — for projectiles stuck in surfaces
  Both modeled on `anvil_pickup_settings.lua`'s throwing axe pickups (refill_amount=1, ammo_kind="thrown", category="ammo"). The `can_interact_func` / `outline_available_func` check `inventory_extension:has_ammo_consuming_weapon_equipped("throwing_javelin")` so only Tuskgor Javelin (or vanilla `we_javelin`) wielders can pick them up — no leaking onto Bardin Slayer's throwing axes. Mirrored into AllPickups + NetworkLookup.pickup_names.
- Both javelin variant defs now declare `projectile_units_template`, `pickup_template_name`, `link_pickup_template_name` so the skin registration cascades them onto the WeaponSkins entry (which BackendUtils.get_item_units overwrites onto the units table at equip time).
- Known: in-flight rotation may read off because `wpn_emp_boar_spear_01_3p` was authored as a held 3P mesh with grip-pose origin, not a balanced projectile origin. If it spins or floats wrong, options are: try `ProjectileUnits.spear` (existing generic spear projectile) or author a real `prj_emp_boar_spear_*_3ps` unit (out-of-scope without unit-authoring tools).

## 0.1.70-dev (2026-05-05)
- Changed: Tuskgor Javelin tuning (`tuskgor_javelin_template`, applies to both `cwv_es_javelin` and `cwv_wh_javelin`):
  - `max_ammo` 15 → 10.
  - Added: in-flight projectile speed multiplier `_TJ_PROJECTILE_SPEED_MULT = 0.9` — applied to `sub_action.speed` on `kind="thrown_projectile"` sub-actions (vanilla javelin throws at `speed = 7000`; ours throws at 6300). Distinct from action timing (`_TJ_SPEED_MULT = 0.5`) which is wind-up + recovery duration; this controls how fast the javelin moves through the air after release.
  - Action speed (0.5x) and damage (2.0x) unchanged.
- Added: throwing-axe-style stick + pickup. The thrown-projectile sub-actions' `impact_data` now strips the vanilla javelin behavior (`link = true` + `wall_nail = true` + `flow_event_on_walls = "teleport_out"` — the auto-recall) and replaces it with the throwing-axe combo (`link_pickup = true` + `pickup_settings = { use_weapon_skin = true, link_hit_zones = { head, neck, torso } }`, lifted from `1h_throwing_axes.lua:80-89`). Stuck javelins now spawn a ground pickup that grants +1 ammo when grabbed, instead of teleporting back into your stack. Combined with `block_ammo_pickup = false` from 0.1.65, this gives the weapon two refill paths: ammo crates and physical javelin retrieval.
- Note: the in-flight + stuck projectile model is still the slim elf javelin (`projectile_units_template = "javelin"` on the skin entry, mirrored from `we_javelin`). The boar spear package doesn't ship a `prj_*_3ps` projectile unit; swapping in a custom one would need a new asset. Held-weapon model is the boar spear as before.

## 0.1.69-dev (2026-05-05)
- Docs only: added a top-of-file ANIMATION ARCHITECTURE banner to `character_weapon_variants.lua` and an inline ANIM ADDENDUM at every `_create_*_template` function and animation-related comment block. The banner restates the load-bearing rule: **1P animations are universal across all six characters and require zero work from this mod — only 3P body anims need cross-character remapping** (`anim_event_3p`, `wield_anim_3p`, `wield_anim_career_3p`). State-machine paths are 1P assets sharing `first_person_base`, so per-character templates are never needed for 1P reasons.
- This is a recurring correction; the redundant annotations exist so future contributors (and AI assistants) can't miss it. See memory note `feedback_1p_animations_universal.md`.
- Retraction: prior speculation in this thread about needing per-character `tuskgor_javelin_template_kruber` / `tuskgor_javelin_template_saltzpyre` clones to handle a 1P state machine mismatch was wrong — the shared template is fine. Future schema work for explicit anim event picks will be 3P-only.

## 0.1.68-dev (2026-05-05)
- Added: `def.scale_3p_only` flag — when `true`, the `GearUtils.create_equipment` hook skips applying scale + offset to the `*_unit_1p` units (held first-person viewport) and only transforms the `*_unit_3p` units. Preview hooks (HeroPreviewer, MenuWorldPreviewer, LootItemUnitPreviewer) are unaffected because they only spawn 3P-style models — so the inventory character preview and illusion browser still show the scaled model.
- Changed: both Tuskgor Javelin variants (`cwv_es_javelin` Kruber + `cwv_wh_javelin` Saltzpyre) now use `left_hand_scale = { 0.80, 0.80, 0.80 }` + `scale_3p_only = true`. Native `wpn_emp_boar_spear_01` is noticeably longer than `we_javelin`; this shrinks it in 3P + previews so the silhouette matches the rest of the ranged kit, while keeping the 1P held viewport at native scale so the throw animation doesn't clip the camera.

## 0.1.67-dev (2026-05-05)
- Added: `cwv_wh_javelin` ("Tuskgor Javelin") — Saltzpyre variant of the Tuskgor Javelin. Same recipe as `cwv_es_javelin` (0.1.58/0.1.65): `we_javelin` base + Tuskgor Spear (`wpn_emp_boar_spear_01`) held model + shared `tuskgor_javelin_template` (15-shot finite stack, no auto-catch reload, 2x damage, 0.5x speed). Available on all four WH careers (Witch Hunter Captain, Bounty Hunter, Zealot, Warrior Priest). Exotic rarity, Scrounger default trait.
- Same anim caveat as the Kruber variant: WH skeleton may lack elf throw events; if 3P anims drop, add remaps in weapon_tweaker.
- Note: spear model is at native scale on both variants (not scaled down) — `wpn_emp_boar_spear_01` is noticeably longer than `we_javelin`. If shrinking is desired, add `left_hand_scale = { x, y, z }` to either def.

## 0.1.65-dev (2026-05-01)
- Added: `tuskgor_javelin_template` — stat-modified clone of `javelin_template` for `cwv_es_javelin`. Behavioural changes:
  - `ammo_data.max_ammo = 15` (up from vanilla 3) — finite stack
  - `ammo_data.block_ammo_pickup = false`, `unique_ammo_type = false` — standard vanilla ammo crates now refill the stack (Kruber's other ranged weapons share the pool)
  - `actions.weapon_reload.default.condition_func` / `chain_condition_func` overridden to `_always_false` — disables the magic auto-catch that vanilla javelin uses to refill itself on-demand. Action stays defined for state-machine/network purposes; it just never fires.
  - `attack_meta_data.minimum_charge_time` doubled (0.55s → 1.1s) — slower wind-up
  - `total_time` and `minimum_hold_time` doubled on `kind="thrown_projectile"` sub-actions — slower throw recovery. `fire_time` left untouched (would desync projectile spawn from anim).
  - All damage profiles cloned with prefix `cwv_tj_`, `attack` doubled (impact/stagger preserved). Melee stabs use existing `_clone_damage_profile` (PowerLevelTemplates string-key shape); throw projectile uses new `_clone_inline_throw_profile` (inline `default_target.power_distribution_near.attack` shape, verified against `damage_profile_templates_dlc_woods.lua:263`).
- Changed: `cwv_es_javelin` def now sets `template = "tuskgor_javelin_template"` and updated description ("Hits like a kicking mule…"). Old "thrown projectile is still the slim javelin" caveat refined — the template is now cloned but the projectile model isn't (boar spear has no `prj_*_3ps` unit in the anvil package).

## 0.1.64-dev (2026-05-01)
- Fixed: ammo-weapon variant skin registration now mirrors the FULL set of fields BackendUtils.get_item_units overwrites from the skin template — `ammo_unit`, `ammo_unit_3p`, `projectile_units_template`, `pickup_template_name`, `link_pickup_template_name` — from the base ItemMasterList entry. Previously only `ammo_unit` was carried (0.1.60), which left the throw projectile / ground-pickup paths exposed to nil-from-skin once the previewer crash was past. Verified via the v0.1.59 crash log (`[LA preview] equip_item key=we_javelin slot=slot_ranged bid=cwv_es_javelin_001 skin=nil` → previewer concatenated nil ammo_unit). Log line now includes `(ammo_unit=..., projectile=...)` for verification.

## 0.1.63-dev (2026-05-01)
- Added: `cwv_es_dual_swords` ("Imperial Dual Swords") — Kruber dual-wield variant cloned from `we_dual_wield_swords`. Both hands hold Kruber's vanilla 1H sword (`wpn_emp_sword_02_t1`); models scaled to {1.0, 0.80, 1.0} (Y -20%, slimmer along depth) on both hands. Available on all four Kruber careers via `_es_all_careers`. Exotic rarity, default trait Swift Slaying.
- Added: `imperial_dual_swords_template` — runtime clone of `dual_wield_swords_template_1` with stat tweaks: -20% speed (`anim_time_scale * 0.80`), +10% damage (`power_distribution.attack * 1.10`), +10% stagger (`power_distribution.impact * 1.10`). Damage profiles cloned with prefix `cwv_eds_`.
- Added: 3P animation redirect to Kruber's mace+sword (`dual_wield_hammer_sword_template`). Sets `wield_anim_3p = "to_dual_hammer_sword_es"` on both the cloned template and the base template's `wield_anim_career_3p` for Kruber careers (matches the inventory-previewer base-template-lookup pattern documented in `feedback_cwv_previewer_template_lookup.md`). Three elf-only attack events with no Kruber mace+sword counterpart are remapped via `anim_event_3p`: `attack_swing_charge_diagonal → attack_swing_charge_left`, `attack_swing_heavy_right → attack_swing_heavy_right_diagonal`, `push_stab → attack_push`. Same-named events fall through and play Kruber's mace+sword animations natively (the empire skeleton authors them under those names).

## 0.1.62-dev (2026-05-01)
- Fixed: javelin variant equip still crashed after 0.1.60 — the `if not WeaponSkins.skins[skin_key]` guard in `_register_variant_skins` skipped re-registration when a stale skin entry from a prior session/version was already present (e.g. a partial reload that re-ran the lua but kept the existing WeaponSkins table). Removed the guard so we always overwrite with current fields. Added `(ammo_unit=...)` to the registration log line so the value is verifiable from the in-game info log.

## 0.1.61-dev (2026-05-01)
- Added: `cwv_es_priest_greathammer` ("Sigmarite Greathammer") — Kruber variant of the Warrior Priest's Greathammer. Same recipe as the Bardin version (`cwv_dr_priest_greathammer`, 0.1.59): clones `wh_2h_hammer` (preserves `two_handed_hammer_priest_template` chargeable smash moveset) and swaps the held model to Kruber's vanilla greathammer (`wpn_empire_2h_hammer_01_t1`). Available on all four Kruber careers via `_es_all_careers`. Exotic rarity, default trait Swift Slaying.
- Known issues — animation workarounds NOT yet implemented for the priest greathammer line:
  - **Both `cwv_dr_priest_greathammer` (Bardin) and `cwv_es_priest_greathammer` (Kruber) inherit `two_handed_hammer_priest_template`, which was authored against Saltzpyre's skeleton.** No 3P/1P anim event coverage probe has been done for dwarf or empire skeletons against this template's events (`attack_swing_charge_right`, `attack_swing_charge`, light/heavy chains, wield pose).
  - Kruber risk is lower (Saltzpyre and Kruber share the empire-human skeleton family, so most events likely already exist natively); Bardin risk is higher (dwarf skeleton, smaller body, likely event mismatch).
  - Workflow when animations break in-game: use `wt animlog` to dump missing events per career, then add remaps either via this mod's template clone (see `_create_elven_sword_shield_template` for the pattern — `anim_event_3p` overrides + `wield_anim_career_3p` patch on the BASE template per `feedback_cwv_previewer_template_lookup.md`) or via weapon_tweaker's career-prefix-aware `_career_anim_redirect`. Process documented in `reference_3p_anim_fix_process.md`.

## 0.1.60-dev (2026-05-01)
- Fixed: equipping `cwv_es_javelin` crashed `world_hero_previewer.lua` ("attempt to concatenate local 'left_hand_unit' (a nil value)"). Root cause: `BackendUtils.get_item_units` overwrites `units.ammo_unit` from the skin template (`WeaponSkins.skins[skin].ammo_unit`) unconditionally when a skin is set. Our custom skin entries omitted `ammo_unit`, so it became nil — and the previewer does `left_hand_unit = ammo_unit` for `is_ammo_weapon` items before concatenating `_3p`. `_register_variant_skins` now mirrors `def.ammo_unit` (fallback: `def.left_hand_unit`) into the skin entry. Required for any cwv variant cloned from an ammo weapon (javelins, future thrown variants).

## 0.1.59-dev (2026-05-01)
- Added: `cwv_dr_priest_greathammer` ("Sigmarite Greathammer") — Bardin variant of the Warrior Priest's Greathammer. Uses `wh_2h_hammer` as base (preserves `two_handed_hammer_priest_template` — the chargeable smash moveset) but swaps the held model to Bardin's vanilla greathammer (`wpn_dw_2h_hammer_01_t1`). Available on all Bardin careers (Ranger Veteran, Ironbreaker, Slayer, Outcast Engineer). Exotic rarity, default trait Swift Slaying.
- Known issues: `two_handed_hammer_priest_template` was authored against Saltzpyre's skeleton — if any 1P/3P anim events are missing on the dwarf skeleton, fix via weapon_tweaker animation remap (per `reference_3p_anim_fix_process.md`).

## 0.1.58-dev (2026-05-01)
- Added: `cwv_es_javelin` ("Tuskgor Javelin") — Kruber variant of the elf javelin. Uses `we_javelin` as base (preserves `javelin_template`, `slot_type=ranged`, `item_type=we_javelin`, `trait_table_name=ranged_ammo`, `projectile_units_template=javelin`) but swaps the held model to the Tuskgor Spear (`wpn_emp_boar_spear_01`). Available on all Kruber careers (Mercenary, Huntsman, Knight, Questing Knight). Exotic rarity, default trait Scrounger (`ranged_replenish_ammo_headshot`).
- Known issues: thrown projectile remains the slim javelin (`Projectiles.javelin` is hardcoded in `javelin_template`); fixing requires a custom template + projectile clone. Kruber's skeleton may also lack some elf throw events (`attack_throw`, `throw_charge`) — if 3P anims are missing in-game, add remaps via weapon_tweaker.

## 0.1.56-dev (2026-05-01)
- Fixed: equipping a cwv variant crashed `BackendUtils.get_item_units` with `attempt to index local 'item_data' (a nil value)`. Vanilla `HeroPreviewer.equip_item` (world_hero_previewer.lua:674) does `item_data = ItemMasterList[item_name]` and passes the result straight into `BackendUtils.get_item_units`. MIL's `add_mod_items_to_local_backend` stores entries in its private table, NOT in ItemMasterList, so the lookup returned nil. `_register_item` now mirrors each cwv entry into `ItemMasterList[def.item_key]` after MIL registration (guarded with `not ItemMasterList[key]` so we don't clobber another mod's registration or a stale hot-reload entry).
- Cleanup: NetworkLookup item_names injection now uses `def.item_key` directly, not the inherited `entry.key` (which would be the base weapon's name from the clone).

## 0.1.55-dev (2026-05-01)
- Added: `entry.cwv_variant = true` marker in `_build_entry`. This is the cross-mod contract: sibling mods (cosmetics_tweaker, weapon_tweaker, future) check `item_data.cwv_variant` in their hooks and skip item-name-keyed overrides when the flag is set. Necessary because cwv items inherit `entry.name` from the base via `table.clone` (e.g. `cwv_es_longsword.name == "es_bastard_sword"`), so without the gate any item-name-keyed override on the base — `_breton_sword_thiccc`, `_weapon_grip_offsets`, hat tinting — would spuriously fire on every cwv variant of that base.
- Tried-and-rejected: clobbering `entry.name = def.item_key` instead of using a flag. The clobber crashed equip because vanilla code falls back to `ItemMasterList[item.name]` lookups that need the inherited name to resolve. See `feedback_cwv_clone_name_clobber.md` for the full incident log and reasoning.
- Note: cosmetics_tweaker has since (v0.7.87) migrated its scale system from item-name-keyed to unit-path-keyed, which makes the flag redundant for the scale path specifically. The flag is still load-bearing for the grip-offset / tint / LA-paint paths and remains the documented cross-mod contract.

## 0.1.46–0.1.54-dev (2026-05-01)

Iterative dev bumps not documented individually here. See `git log -- character_weapon_variants/` for the actual history. Going forward, please add a heading per substantive change set.

## 0.1.45-dev (2026-05-01)
- Added: `mod.weapon_analogues` table + `mod.get_analogues(item_key)` getter — public API exposing vanilla weapon items that are mechanically analogous and can share cosmetics. Initial mapping: `es_2h_sword ↔ wh_2h_sword` (Kruber Greatsword ↔ Saltzpyre Falchion). Consumed by cosmetics_tweaker's LA bridge to widen cross-character cosmetic targeting when this mod is loaded.

## 0.1.25-dev (2026-05-01)
- Added: Imperial Longsword — `cwv_es_longsword` (default, power 5) and `cwv_es_longsword_veteran` ("Halfling Splitter", exotic rarity). Uses `bastard_sword_template` as base with a custom `imperial_longsword_template` clone: -15% damage, +15% speed (anim_time_scale), +15% cleave, -15% stagger. Available on all Kruber careers.
- Added: `imperial_longsword_template` — runtime clone of `bastard_sword_template` with modified stat multipliers. Clones all 6 melee damage profiles (`DamageProfileTemplates` + `PowerLevelTemplates`) with `cwv_il_` prefix, modifying `power_distribution.attack` (damage), `power_distribution.impact` (stagger), and `cleave_distribution` values. Multiplies `anim_time_scale` on all sub-actions for speed.
- Added: model scaling system — `right_hand_scale` / `left_hand_scale` fields on variant definitions apply `Unit.set_local_scale` across all three rendering paths (GearUtils.create_equipment, HeroPreviewer._spawn_item, LootItemUnitPreviewer.spawn_units). Base longsword: 1h sword model stretched Z +15% ({1.0, 1.0, 1.15}). Veteran: greatsword model thinned X 0.65 + shortened Z -15% ({0.65, 1.0, 0.85}).
- Changed: `_build_entry` now supports `template` override and clears `required_dlc` on cloned entries

## 0.1.24-dev (2026-05-01)
- Fixed: crash `NetworkLookup.lua Table item_names does not contain key` when equipping LA bridge hats. Root cause: `MoreItemsLibrary.add_mod_items_to_local_backend` does NOT inject into `NetworkLookup.item_names` (only `add_mod_items_to_masterlist` does). Items registered via MIL were invisible to the network serialization layer. Now manually inject all mod-created item keys into `NetworkLookup.item_names` using `rawset` after MIL registration — covers variant weapons, custom illusions, and LA bridge hats (cosmetics_tweaker fix).

## 0.1.22-dev (2026-05-01)
- Fixed: `ActionWield.start` hook failed — `ActionWield` isn't loaded at mod init. Changed to `hook_safe("ActionWield", "client_owner_start_action", ...)` which uses lazy string-form resolution and fires after the original (so `self.new_slot` is available for weapon tracking).
- Fixed: removed incorrect `_weapon_remap` table that remapped 9 events. Template analysis shows 12/14 sword+shield events already exist on elf's skeleton (confirmed via elf 1h sword, dual swords, sword+dagger, 2h sword, spear, spear+shield templates). Only `attack_swing_charge_right_pose` (L3/H2 charge) is missing and remapped to `attack_swing_charge_right_diagonal_pose`.

## 0.1.20-dev (2026-04-30)
- Fixed: elf sword+shield missing animations — L1, H1, H3 didn't play because elf's skeleton lacks those specific events from Kruber's sword+shield template. Added career-scoped redirects:
  - `attack_swing_charge` → `attack_swing_charge_left` (L1 charge)
  - `attack_swing_heavy` → `attack_swing_heavy_left` (H1 shield slam)
  - `attack_swing_left_diagonal` → `attack_swing_left` (L1 release)
- Removed verbose info logging from animation redirects to reduce log spam

## 0.1.19-dev (2026-04-30)
- Added: cross-character greatsword illusions — all of Saltzpyre's greatsword skins selectable on Kruber's greatsword and vice versa via cosmetics menu. Includes base skins, runed/red illusions, bogenhafen (purple glow), geheimnisnacht (golden glow), and weavebound (magic) variants. 9 Saltzpyre→Kruber skins, 11 Kruber→Saltzpyre skins.
- Added: `_custom_illusions` system — clones all visual data (name, rarity, icon, glow material, model) from vanilla `WeaponSkins.skins` at runtime. No manual field copying needed — just `skin_key`, `matching_weapon`, `source_skin`, and `can_wield`.
- Added: `_register_custom_illusions()` — injects into `ItemMasterList`, `WeaponSkins.skins`, `skin_combinations` (correct rarity tier), and `NetworkLookup.weapon_skins`. Hooks `get_unlocked_weapon_skins` to mark custom skins as unlocked.
- Added: Elf Sword and Shield — `cwv_we_sword_shield` (magic, weave template) and `cwv_we_sword_shield_veteran` (unique/veteran with Opportunist + block cost + power vs skaven). Uses Kruber's `es_sword_shield` template (`one_handed_sword_shield_template_1`) with elf's weave sword (`wpn_we_sword_03_t1_magic_01`) and weave spear+shield's shield (`wpn_we_shield_02_magic_01`). Available on all elf careers.
- Added: animation redirect system — remaps `to_1h_sword_shield` wield anim to `to_1h_spear_shield` for elf careers, plus suffix-based redirect for any `_1h_sword_shield` suffixed events. Hooks `Unit.animation_event` with career detection.
- Changed: `cwv_es_axe_shield` base variant from magic (weave) to plentiful (green) rarity — now functions as the standard blacksmith's template item with no traits or properties.

## 0.1.18-dev (2026-04-30)
- Fixed: veteran variant showed as template item (no rarity color, no cosmetics menu). Root cause: GiveWeapon pattern requires `entry.rarity = "default"` and `CustomData.rarity = "default"` during registration, then post-registration the actual rarity is set on the live backend item object (`item.rarity`, `item.data.rarity`, `item.CustomData.rarity`).
- Fixed: kept `skin_combination_table` from base weapon instead of clearing it — needed for the cosmetics/illusion menu to appear.
- Fixed: property values use `1` (max roll) instead of decimal fractions — matches GiveWeapon's format.

## 0.1.17-dev (2026-04-30)
- Fixed: auto-registration crashed because backend is nil at mod init. Now deferred via `mod:hook_safe("StateInGameRunning", "on_enter", ...)` — items register when entering the keep/mission, where the backend is guaranteed ready.

## 0.1.16-dev (2026-04-30)
- Changed: veteran variant now uses Opportunist trait (`melee_counter_push_power`), 30% block cost reduction, 10% power vs skaven
- Fixed: auto-registration now runs at mod init (same timing as cosmetics_tweaker's LA bridge) instead of `StateInGameRunning` — weapons appear in inventory immediately without needing to enter a mission first

## 0.1.14-dev (2026-04-30)
- Changed: exotic variant → veteran (unique) rarity so it functions as a proper weapon with properties and traits, not a weapon template
- Added: auto-registration — all variant weapons are automatically added to inventory when entering a game (no `cwv_give` needed). Uses stable backend IDs to prevent duplicates across sessions.
- Changed: `cwv_give` now checks for duplicates and uses stable IDs instead of time-based ones

## 0.1.13-dev (2026-04-30)
- Added: exotic-rarity variant `cwv_es_axe_shield_exotic` — "Imperial Axe and Shield" with power level 300, `melee_attack_speed_on_crit` trait, and attack speed + crit chance properties. Functions as a proper weapon with stats, not just a template.
- Changed: `_build_entry` now serializes traits and properties from variant definitions into `CustomData` JSON strings and parallel Lua tables, matching the format expected by MoreItemsLibrary and the backend.

## 0.1.12-dev (2026-04-30)
- Fixed: `NetworkLookup.weapon_skins` has an error-throwing `__index` metamethod — accessing a missing key crashes instead of returning nil. Now uses `rawget`/`rawset` to bypass the metatable when checking and injecting the custom skin key.

## 0.1.11-dev (2026-04-30)
- Fixed: crash `NetworkLookup.weapon_skins does not contain key: cwv_es_axe_shield_skin` — custom skins must be injected into `NetworkLookup.weapon_skins` for network serialization. The skin is registered in `WeaponSkins.skins` after `NetworkLookup` is built, so it needs a manual append.

## 0.1.10-dev (2026-04-30)
- Fixed: crash `Material not found in Gui` — `inventory_icon` and `hud_icon` are different systems. `inventory_icon` uses texture keys like `icon_wpn_dw_shield_01_axe`, while `hud_icon` uses keys like `weapon_generic_icon_axe_and_sheild`. Using the wrong type in either field crashes the UI renderer.

## 0.1.9-dev (2026-04-30)
- Fixed: crash `Material 'weapon_generic_icon_staff_3' not found in Gui` — that icon key doesn't exist in the GUI atlas. Replaced with `weapon_generic_icon_axe_and_sheild` (Bardin's axe+shield HUD icon) as a working placeholder

## 0.1.8-dev (2026-04-30)
- Fixed: inventory preview showed Bardin's models because `BackendUtils.get_item_units` resolves units through the item's skin, not the base entry's unit paths. Now registers a custom `WeaponSkins.skins` entry per variant with the correct unit paths, and sets it as the item's skin via `mod_data.CustomData.skin`

## 0.1.7-dev (2026-04-30)
- Fixed: inventory preview showed Bardin's model because skin resolution overrode our unit paths — now clears `skin_combination_table` on cloned entries so the entry's `right_hand_unit`/`left_hand_unit` are used directly

## 0.1.6-dev (2026-04-30)
- Fixed: `cwv_give` items now override `display_name` and `description` with custom loc keys so they show our names instead of the base weapon's (e.g. "Axe and Shield" instead of Bardin's name)

## 0.1.5-dev (2026-04-30)
- Added: Saltzpyre's one-handed axe (`wh_1h_axe`) unlocked on all Kruber careers (Mercenary, Huntsman, Foot Knight, Grail Knight) via `can_wield` patch at mod load
- Added: `_weapon_unlocks` table for declarative cross-character weapon unlocks

## 0.1.4-dev (2026-04-30)
- Fixed: `ItemHelper.mark_backend_id_as_new` was called with a table `{backend_id}` instead of the string `backend_id`
- Fixed: `mark_backend_id_as_new` was called before `_refresh()`, so the backend hadn't indexed the new item yet — reordered to refresh first, then mark
- Added pcall guard around `mark_backend_id_as_new` in case the item isn't found

## 0.1.3-dev (2026-04-30)
- Fixed: removed init-time item registration — backend is not ready at mod load; `add_mod_items_to_local_backend` now called on-demand via `cwv_give` command only
- Fixed: no longer overwrites `display_name`/`description` on cloned ItemMasterList entry — MoreItemsLibrary requires these to be real strings, not localization keys; custom names handled via Localize hook instead
- Fixed: base weapon key corrected from `dr_1h_axe_shield` (item_type) to `dr_shield_axe` (actual ItemMasterList key)

## 0.1.2-dev (2026-04-30)
- Fixed: base weapon key `dr_1h_axe_shield` → `dr_shield_axe`

## 0.1.1-dev (2026-04-30)
- Added first variant definition: `cwv_es_axe_shield` (Weave Forged Axe and Shield for Kruber)
  - Mainhand: Saltzpyre's weave-forged hatchet (`wpn_axe_hatchet_t2_magic_01`)
  - Offhand: Kruber's weave-forged CW spear+shield shield (`wpn_es_deus_shield_02_magic`)
  - Base template: Bardin's `dr_shield_axe` (`one_hand_axe_shield_template_1`)
  - Rarity: magic (weavebound)
  - Available on: Mercenary, Huntsman, Foot Knight
- Added `cwv_give <item_key>` command to spawn variant weapons
- Added `cwv` status command
- Added companion mod detection (weapon_tweaker, cosmetics_tweaker)
- Added Localize hook for custom display names and descriptions

## 0.1.0-dev (2026-04-29)
- Initial mod scaffold created via VMB
- Workshop item created (ID: 3716869446, private)
- MoreItemsLibrary integration structure
- Cross-mod architecture documented in `CROSS_MOD_ARCHITECTURE.md`
