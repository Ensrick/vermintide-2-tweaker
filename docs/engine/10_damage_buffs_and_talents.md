# Engine reference 10 - Damage, buffs, talents and health

Audience: maintainers and AI agents working on crt / ct / bt-descendant code. Every claim
cites a file:line. Vanilla paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; our paths are relative to
`C:\Users\danjo\source\repos\vermintide-2-tweaker`. Line numbers are against the decompile
as of 2026-07-11; re-verify after a game patch. Anything not verified is tagged
`[unverified]`.

---

## 1. Architecture map

### 1.1 Damage

| File | Class / global | Single responsibility |
|---|---|---|
| `scripts/helpers/damage_utils.lua` | `DamageUtils` (stateless table) | ALL damage/stagger/heal/DoT/explosion math + the network entry points (`add_damage_network` :1745, `add_damage_network_player` :1864, `heal_network` :2484, `apply_dot` :3780, `server_apply_hit` :3666, `create_explosion` :1049) |
| `scripts/entity_system/systems/damage/health_system.lua` | `HealthSystem` | Hosts health extensions per unit; owns every damage/heal RPC receiver (`rpc_add_damage` :368, `rpc_add_damage_network` :439, `rpc_heal` :489, `rpc_request_heal` :547, `rpc_request_convert_temp` :582, `rpc_take_falling_damage` :633) |
| `scripts/unit_extensions/generic/generic_health_extension.lua` | `GenericHealthExtension` | AI/prop health. Model is "damage_taken accumulator vs max": `add_damage` :294, `add_heal` :425, damage-history ring buffer `_add_to_damage_history_buffer` :238 |
| `scripts/unit_extensions/default_player_unit/player_unit_health_extension.lua` | `PlayerUnitHealthExtension` | Player health. State lives in GameSession game-object fields (`current_health`, `current_temporary_health`, `max_health`, `uncursed_max_health` - written :318-381), NOT in Lua fields. Knockdown/revive :223-304, THP degen :383-415, `add_damage` :530, `add_heal` :842, permanent/temp conversion API :1161-1223 |
| `scripts/entity_system/systems/damage/hit_reaction_system.lua` | `HitReactionSystem` | Thin extension host for `GenericHitReactionExtension`; no logic (:1-90) |
| `scripts/unit_extensions/generic/generic_hit_reaction_extension.lua` | `GenericHitReactionExtension` | Consumes the damage-history buffer each frame (`update` :188), resolves effect templates (`_resolve_effects` :308), plays dismemberment/push/wall-nail (`_execute_effect` :477) |
| `scripts/unit_extensions/generic/hit_reactions.lua` | `HitReactions.templates` | Gameplay-side reaction table (ai_default etc., :61); `ignored_damage_types` :6-20 filters THP degen/heals/pushes out of reactions |
| `scripts/settings/difficulty_settings.lua` | `DifficultySettings` | Per-rank knobs: `power_level_cap`/`power_level_max_target` (:20-21 normal), `friendly_fire_ranged/_melee/_multiplier` (:92-94 harder), `stagger_damage_multiplier`/`min_stagger_damage_coefficient` (:25, :19), `wounds`, `max_hp`, `respawn` percentages (:29-34) |
| `scripts/managers/difficulty/difficulty_manager.lua` | `DifficultyManager` | Difficulty accessors: `get_difficulty` :59, `get_difficulty_rank` :63, `get_difficulty_value_from_table` :71 (per-difficulty-key lookup with `fallback_difficulty`) |
| `scripts/helpers/action_utils.lua` | `ActionUtils` | Hero power scaling: `scale_power_levels` :157 applies the difficulty `power_level_cap` soft-cap (:162-172); `get_power_level_percentage` :15 |

### 1.2 Buffs

| File | Class / global | Single responsibility |
|---|---|---|
| `scripts/unit_extensions/default_player_unit/buffs/buff_extension.lua` | `BuffExtension` | Per-unit buff store. `add_buff` :165, stacking :520, stat-buff registry `_add_stat_buff` :635, update/tick loop :713, `remove_buff` :889, proc dispatch `trigger_procs` :1303, stat readers `apply_buffs_to_value` :1391 / `get_buff_value` :1367, sync-id machinery :1519-1687 |
| `scripts/entity_system/systems/buff/buff_system.lua` | `BuffSystem` | Networked buff add/remove. `add_buff` :277 (server-controlled ids :206-237), `rpc_add_buff` :417, group buffs :472-540, volume buffs :353-415, param-packing synced buffs `add_buff_synced` :849 + `rpc_add_buff_synced*` :890-1043, hot-join sync :66 / :1067 |
| `scripts/unit_extensions/default_player_unit/buffs/buff_templates.lua` | `BuffTemplates`, `StatBuffApplicationMethods` :26-167, `ProcEvents` :186, `ProcFunctions` :323, `StackingBuffFunctions` :4149 | The template data + the proc function registry. End-of-file merges: `OldTalentBuffTemplates` :9578, per-hero `TalentBuffTemplates` :9580-9582, weapon/weave trait+property buffs :9584-9587 |
| `scripts/unit_extensions/default_player_unit/buffs/buff_function_templates.lua` | `BuffFunctionTemplates.functions` :97 | apply/update/remove function bodies referenced by name from templates (`apply_buff_func` etc.) |
| `scripts/unit_extensions/default_player_unit/buffs/buff_utils.lua` | `BuffUtils` | `get_buff_template(name, mechanism)` :256 - THE template resolver (reads `BuffTemplates[name]`, applies `MechanismOverrides`); balefire DoT variant generator :267 |
| `scripts/network_lookup/network_lookup.lua` | `NetworkLookup.buff_templates` :1144 | int<->name table for every buff RPC. Built by `create_lookup` :38-47 (a bare `pairs()` walk of `BuffTemplates`), then sealed with an ERROR-on-missing-key `__index` metatable :2346-2367 applied to every lookup table :2386-2388 |

### 1.3 Talents

| File | Class / global | Single responsibility |
|---|---|---|
| `scripts/managers/talents/talent_settings.lua` | `Talents`, `TalentIDLookup` :23, `TalentTrees` walk :43-62 | Requires per-hero files (:5-10, `DLCUtils.require_list` :10), builds the name->{talent_id, hero_name} lookup, stamps tree/row/column onto each talent |
| `scripts/managers/talents/talent_settings_<hero>.lua` + `scripts/settings/dlcs/*/talent_settings_*.lua` | per-hero `Talents[hero]`, `TalentBuffTemplates[hero]` | Talent rows: each entry has `buffs` / `client_buffs` / `server_buffs` name lists, `buffer` routing, `mechanism_overrides` |
| `scripts/helpers/talent_utils.lua` | `TalentUtils` | `get_talent_by_id` :12 (applies `mechanism_overrides` via shallow copy :25-40), `get_talent_attribute` :45 |
| `scripts/unit_extensions/default_player_unit/talents/talent_extension.lua` | `TalentExtension` | `talents_changed` :48 orchestrates re-apply; `apply_buffs_from_talents` :78 (the buffer-routing switch :117); `_clear_buffs_from_talents` :207; `has_talent` :221 (returns false under the `whiterun` mutator :222-224); RPC send `_send_rpc_sync_talents` :64 |
| `scripts/unit_extensions/default_player_unit/talents/husk_talent_extension.lua` | `HuskTalentExtension` | Remote-player mirror of talent ids [unverified detail - not read this pass] |
| `scripts/entity_system/systems/talents/talent_system.lua` | `TalentSystem` | `rpc_sync_talents` receiver :37 (server relays to other clients :49), hot-join re-send :66-68 |

### 1.4 Where our code sits

| Mod | File | Role in this subsystem |
|---|---|---|
| crt (`career_tweaker/`) | `scripts/mods/career_tweaker/career_tweaker.lua` | Talent SWAPS: re-binds `TalentTrees[profile][index]` and `CareerSettings` pointers (:266-321), restores on disable (:561-598); talent dump harness :643 |
| crt | `career_tweaker_balance.lua` | The live talent-rework engine. Unconditional `crt_*` buff-name pre-registration :36-103; per-toggle patches mutate `BuffTemplates[buff].buffs[1][field]` (:112-121); hooks (`TalentExtension.has_talent_perk` :2958, `ActionUtils.get_critical_strike_chance` :2985, `TalentExtension.apply_buffs_from_talents` hook_safe :3603, THP proc :3481-3496) |
| crt | `career_tweaker_armor_overcharge.lua` | Exactly two hooks (:54): `DamageUtils.apply_buffs_to_damage` :212 (gromril + Unchained overcharge shims) and `PlayerUnitHealthExtension.add_damage` :281 (Necromancer counter shim) |
| crt | `career_tweaker_big_rebalance.lua` | BR ON ICE - inert stub early-return :32; legacy registration helpers :112-158 kept for reference |
| ct (`chaos_wastes_tweaker_dev/`) | `chaos_wastes_tweaker_dev.lua` | Boon system: `_register_in_network_lookup` :10192-10201, `inject_dormant_boon` :10211-10336 (unconditional network registration, toggle-gated pool insert :10343-10378), meta boons `_make_meta_proc` :11117 / `register_meta_boon` :11142, kill-heal boon proc :12105-12116 |
| bt (RETIRED) | `_archive/buff_tweaker_v0.1.12-alpha/scripts/mods/buff_tweaker/buff_tweaker_registrations.lua` | The canonical Big Rebalance shared registration list: 272 buff templates + 37 damage profiles + 16 explosion templates + 3 stat-buff methods, alphabetically sorted, order LOAD-BEARING (:1-56). Consumers (wt/ct/et/crt) gate on `(get_mod("bt") or {}).is_br_active` and go inert without it (`CLAUDE.md` Mod Directory, bt row) |

---

## 2. Lifecycle and data flow

### 2.1 Boot order (why registration timing matters)

1. `BuffTemplates` is populated at file parse (`buff_templates.lua:4362`), then merged with
   `OldTalentBuffTemplates`, every hero's `TalentBuffTemplates`, and weapon/weave
   trait/property buffs (`buff_templates.lua:9578-9587`). Deus (CW) boon buffs merge in via
   `table.merge_recursive(dlc_settings.buff_templates, DeusPowerUpBuffTemplates)`
   (`scripts/settings/dlcs/morris/morris_buff_settings.lua:7310`).
2. `NetworkLookup.buff_templates` is then built from the merged table by a bare `pairs()`
   walk (`network_lookup.lua:38-47`, table at :1144-1146), and every lookup table is sealed
   with an error-on-missing-key `__index` metatable (`network_lookup.lua:2346-2367`,
   applied :2386-2388).
3. Mods load AFTER all of this. Consequences:
   - Runtime writes to `TalentBuffTemplates[hero]` or `DeusPowerUpBuffTemplates` alone do
     NOTHING - the merge already ran. Write `BuffTemplates[name]` directly as well
     (crt does both: `career_tweaker_big_rebalance.lua:123-135`; ct documents it:
     `chaos_wastes_tweaker_dev.lua:10301-10310`).
   - A mod-added template is invisible to the wire until the mod ALSO appends the
     `idx<->name` pair into `NetworkLookup.buff_templates`
     (crt: `career_tweaker_balance.lua:95-99`; ct: `chaos_wastes_tweaker_dev.lua:10192-10201`).
   - Appended indices are `#table + 1`, so cross-peer index equality holds only if every
     peer appends the SAME names in the SAME order (see section 4.2).

### 2.2 Player spawn and talent application

1. `TalentExtension.extensions_ready` (:15) caches sibling extensions; on
   `talents_changed` (:48) the order is: package deps check -> `apply_buffs_from_talents`
   -> career weapon index -> `_check_resync` -> `rpc_sync_talents` broadcast (:57-59).
2. `apply_buffs_from_talents` (`talent_extension.lua:78-166`) clears previous talent buffs
   (:101) then, per talent, routes each buff-name list by the talent's `buffer` field
   (:117): default/`"client"` = owner (or server-bot) only; `"server"` = server only;
   `"both"` = server + owner; `"all"` = everyone. `client_buffs` apply on owner/bot
   (:139-150), `server_buffs` on server (:152-163). This is why a stat rework must exist
   in `BuffTemplates` on BOTH the owner's machine and the host: each side adds its own
   local instance.
3. `TalentSystem.rpc_sync_talents` (:37) sets talent ids on the husk extension; the
   server relays to remaining clients (:49); hot-join re-sends everyone's ids (:66-68).

### 2.3 A melee/ranged hit, in order

1. Attacker-side weapon action computes power level (`ActionUtils.scale_power_levels`
   :157 applies the difficulty cap :162-172) and calls
   `DamageUtils.add_damage_network_player` (:1864) / `server_apply_hit` (:3666), which
   compute damage via `calculate_damage` (:449) -> `do_damage_calculation` (:119).
   Difficulty enters here: `DifficultySettings[difficulty_level]` (:124), killing-blow
   uses per-rank breed max health (:357-359), friendly fire multiplies by
   `difficulty_settings.friendly_fire_multiplier` (:367-385).
2. `DamageUtils.add_damage_network` (:1745): immunity check (:1761) -> mechanism
   custom-setting multiplier (:1776-1782) -> **server-only** victim-side buff application
   `apply_buffs_to_damage` (:1790) -> `networkify_damage` quantization (:1793) ->
   attacker's `on_damage_dealt` proc may REWRITE `damage_amount` via the modifiable
   FrameTable (:1802-1809) -> if server: per-victim `health_extension:add_damage`
   (:1816-1832); if client: `rpc_add_damage_network` to server (:1849).
3. `apply_buffs_to_damage` (:2134-2453) is the victim-side stat-buff chokepoint:
   `protection_skaven/chaos` (:2163-2167), `protection_aoe` (:2169-2171), `damage_taken`
   + `damage_taken_elites` (:2173-2179, gated by `IGNORE_DAMAGE_REDUCTION_DAMAGE_SOURCE`
   :2128-2132), melee/ranged taken (:2181-2185), knocked-down (:2190-2194), Unchained
   `damage_taken_to_overcharge` conversion incl. the client RPC
   `rpc_damage_taken_overcharge` (:2196-2224).
4. `PlayerUnitHealthExtension.add_damage` (:530): history buffer + statistics (:658-662),
   `on_damage_taken` procs (:700-704, skipped for THP degen), `ignore_death` perk floor
   (:706). AI path: `GenericHealthExtension.add_damage` (:294) accumulates
   `damage_taken`, syncs via `_sync_out_damage` (:400).
5. Hit reactions: both health extensions append to the damage-history ring
   (`generic_health_extension.lua:238`); `GenericHitReactionExtension.update` (:188)
   drains it next frame and plays effects. Damage types in
   `hit_reactions.lua:6-20` (heals, THP degen, pushes...) never produce reactions.

### 2.4 Heals and THP

1. `DamageUtils.heal_network` (:2484) - **server-only** (`fassert` :2485; note
   BUG_CLASSES 29 cites :2636 from an older decompile). Flow: `healing_immune` perk
   (:2489) -> `apply_buffs_to_heal` (:2563: `healing_received` stat :2572,
   `shared_health_pool` split :2575-2599) -> per healed unit `add_heal` + `on_healed` /
   `on_healed_ally` / `on_healed_consumeable` procs (:2513-2548) -> wounded-clear
   (:2545-2547).
2. `PlayerUnitHealthExtension.add_heal` (:842, server branch :856): permanent-vs-temp
   split at :865-877. `status_extension:is_permanent_heal(heal_type)`
   (`generic_status_extension.lua:2230-2248`) whitelists
   `healing_draught | bandage | bandage_trinket | buff_shared_medpack | career_passive |
   health_regen | debug | health_conversion` (:2247); everything else - including
   `heal_from_proc` - lands in `current_temporary_health` (:874-877). Permanent heals
   EAT temp health first (:866-872). Any heal (except `career_passive`) resets the degen
   timer (:879-884). Server then RPCs `rpc_heal` to clients (:894).
3. THP decay is server-tick inside `PlayerUnitHealthExtension.update` (:383-415):
   wounded vs normal degen settings (:384-390), versus multipliers (:395-403), damage is
   dealt as `temporary_health_degen` via `add_damage_network` (:410). Knockdown zeroes
   permanent health and refills temp to max (:328-330); revive restores
   `_percent_health_on_revive` / temp percent with `temp_to_permanent_health` and
   `full_health_revive` perk branches (:331-346). Max-health changes rescale both pools
   proportionally every server tick (:348-361) - so a `max_health` stat buff "just works"
   with no refresh API.
4. Client-initiated heals go through `HealthSystem.rpc_request_heal` (:547) /
   `rpc_request_convert_temp` (:582).

### 2.5 Buff instance lifecycle

1. `BuffExtension.add_buff(template_name, params)` (:165): frozen-unit bail (:168-170,
   returns nil - callers must nil-check), template via `BuffUtils.get_buff_template`
   (:173; nil template = crash at :174 `#sub_buffs` - ct's reason for mirroring writes
   into `BuffTemplates`, `chaos_wastes_tweaker_dev.lua:10301-10306`).
2. Per sub-buff: `apply_condition` (:187-191), `variable_value` / `external_optional_*`
   param overrides (:206-251 - the engine's sanctioned per-application override channel),
   `duration_modifier_func` (:253-255), stacking gate `_add_stacking_buff` (:274),
   buff-area unit spawn (:364-383), `apply_buff_func` via
   `BuffFunctionTemplates.functions` (:389-401), stat-buff registration (:412-416),
   event-buff registration for procs (:418-433), VFX/SFX (:441-477). Returns
   `id, sub_buffs_added, first_buff` (:517).
3. Stat buffs are read at consumption sites through `apply_buffs_to_value` (:1391-1448)
   using `StatBuffApplicationMethods` (`buff_templates.lua:26-167`): `stacking_multiplier`
   (additive multipliers), `stacking_multiplier_multiplicative` (`damage_taken` :50),
   `stacking_bonus`, `proc`, `min` (`max_damage_taken` :103).
4. Procs: `trigger_procs(event, ...)` (:1303) filters by `buff.template.authority`
   (`has_authority` :1297-1301: default = fires on server for AI-owned, on owner for
   players), PRD proc chance (:1284-1291), `proc_cooldown` (:1331-1332), sorts by
   `proc_weight` (:1344), resolves the function from the FLAT global `ProcFunctions`
   (:1351) - NOT `BuffFunctionTemplates.functions` - and removes `remove_on_proc` buffs
   (:1354-1364). ct burned on the two-registry split (v0.7.64 note,
   `chaos_wastes_tweaker_dev.lua:11158-11166`): a name used as both `apply_buff_func`
   and proc `buff_func` must be written into BOTH tables.
5. `remove_buff` (:889) / `_remove_sub_buff` (:939) unwind stat buffs, perks, VFX, and
   free sync ids.

### 2.6 Networked buffs (three distinct mechanisms)

| Mechanism | Entry | Wire format | Notes |
|---|---|---|---|
| Plain broadcast | `BuffSystem.add_buff(unit, name, attacker, is_server_controlled)` `buff_system.lua:277` | `rpc_add_buff` with `NetworkLookup.buff_templates[name]` int (:302-308) | Receiver `rpc_add_buff` :417. Server-controlled variant allocates a server_buff_id (:206-237, hard `ferror` at cap :233 - see the CW boon AoE overflow memory) and FASSERTS if any sub-buff has a duration (:259) |
| Param-synced | `BuffSystem.add_buff_synced(unit, name, sync_type, params)` :849 | `rpc_add_buff_synced(_params)` :890/:957 with packed param ids (:601-765) | Used for buffs needing attacker/power-level context on all peers; hot-join replay :1067 |
| Group buffs | `rpc_add_group_buff` :472 | `NetworkLookup.group_buff_templates` | Re-applied to late spawners in `BuffExtension.extensions_ready` :76-93 |

All three encode the template as an INT INDEX into `NetworkLookup.buff_templates`. This
is the root of every peer-parity crash class in section 4.2.

---

## 3. Hookable seams

Rule zero for all of these: grep the mod for an existing hook on the same
`(Class, method)` first (repo NON-NEGOTIABLE 8; VMF silently drops the second).

| Seam | Safe pattern | Traps |
|---|---|---|
| `DamageUtils.apply_buffs_to_damage` | Table-form `mod:hook(DamageUtils, "apply_buffs_to_damage", ...)`; fast early-out when no toggle is on; capture all returns; `pcall(func, ...)` + restore any shims + re-`error` on failure. Live example: `career_tweaker_armor_overcharge.lua:212-273` | Runs SERVER-side only inside `add_damage_network` (:1790). One hook per mod - crt owns it for crt features (:54 banner). Plain-table target: hook at file load, not lazily |
| `PlayerUnitHealthExtension.add_damage` | Full 18-param signature named verbatim (never `...`-collapse a networked signature - `reference_vmf_hook_drops_skip_sync_rpc_loop`). Live example: `career_tweaker_armor_overcharge.lua:281-317` | Fires per-victim on the victim's own peer AND on the server for remote units; gate by `self.is_server` / ownership if the effect must be single-sided |
| `TalentExtension.has_talent_perk` / `has_talent` | Wrapper returning modified verdicts (`career_tweaker_balance.lua:2958`) | Both return false wholesale under the `whiterun` mutator (`talent_extension.lua:222-224, :260-262 [unverified exact line for perk]`) - do not "fix" that |
| `TalentExtension.apply_buffs_from_talents` (hook_safe) | Post-pass to add/patch talent-driven buffs after vanilla applied (`career_tweaker_balance.lua:3603`) | Runs on owner AND server per the buffer table (section 2.2) - the post-pass runs wherever vanilla ran; make the body idempotent |
| Template data mutation (no hook) | Patch `BuffTemplates[name].buffs[1][field]` at toggle-on, restore originals at toggle-off (`career_tweaker_balance.lua:112-121`). Takes effect on the next `apply_buffs_from_talents` (mission load / talent change) | Mutation is GLOBAL - hits every unit and career using the template (memory `reference_wt_shared_template_global_mutation_breaks_native`). Never mutate a LIVE buff instance's `template` - it is the shared table (`buff_extension.lua:304`) |
| Per-application override (no hook) | Pass `params.external_optional_multiplier/_bonus/_duration/...` to `add_buff` (`buff_extension.lua:240-246`) when OUR code is the caller | Only covers buffs we add ourselves; vanilla add sites pass their own params |
| New buff template registration | Write `BuffTemplates[name]` + append `NetworkLookup.buff_templates` pairwise, UNCONDITIONALLY at mod load, sorted (`career_tweaker_balance.lua:83-103`); talent-tagged names also into `TalentBuffTemplates[hero]` (`career_tweaker_big_rebalance.lua:123-135`) | Existence checks on NetworkLookup MUST be `rawget` - the `__index` metatable errors (`network_lookup.lua:2360-2367`; burn note `career_tweaker_balance.lua:86-90`). Never tie registration to a toggle (section 4.2) |
| `ProcFunctions[name]` / `BuffFunctionTemplates.functions[name]` | Plain global writes; resolved by name at proc time (`buff_extension.lua:1351`) / apply time (:400) | Write BOTH tables when one name serves both roles (`chaos_wastes_tweaker_dev.lua:11158-11166`). Proc bodies run on the proc owner's machine - anything server-authoritative inside them needs an `is_server` gate (section 4.1) |
| `DeusPowerUpTemplates[name]` mutation (ct boon tweaks) | Mutate `DeusPowerUpTemplates` (read live by the apply path, `deus_power_up_utils.lua:250` per ct's note `chaos_wastes_tweaker_dev.lua:9204-9213`) | Mutating `DeusPowerUpBuffTemplates` does nothing after boot (merge already ran, `morris_buff_settings.lua:7310`) |
| Talent swap (crt) | Re-bind `TalentTrees[profile][tree_index]` and CareerSettings pointers, saving originals (`career_tweaker.lua:266-321`) | UI caches: refresh `HeroWindowTalents` on swap (`career_tweaker.lua:216-226`). Swaps are LOCAL data - both peers need crt for consistent bot/remote behavior [unverified scope of desync] |
| `GameSession` health fields | Server-side `GameSession.set_game_object_field(game, go_id, "current_health"/..., v)` as vanilla does (`player_unit_health_extension.lua:380-381`) | Values quantized by `DamageUtils.networkify_health` (:377-378); never write from a client |
| Heals from mod code | `DamageUtils.heal_network(unit, unit, amount, heal_type)` behind `Managers.player.is_server` (vanilla gate pattern `buff_templates.lua:325`, ours `career_tweaker_balance.lua:3494`, `chaos_wastes_tweaker_dev.lua:12112`) | Pick heal_type by intent: THP = `heal_from_proc`; permanent green = `health_regen` (whitelist `generic_status_extension.lua:2247`; note `health_regen` does NOT clear wounded state, :2251) |

---

## 4. Traps and crash classes

### 4.1 Client-side proc calls a server-only API - BUG_CLASSES 29 (#405 crt, #406 ct)

`trigger_procs` runs on the proc owner's LOCAL machine (`buff_extension.lua:1303` +
authority filter :1297-1301). `DamageUtils.heal_network` fasserts "Only server can heal"
(`damage_utils.lua:2485`). Every vanilla healing proc is gated
`Managers.player.is_server` (`buff_templates.lua:325, :361, :404`) - the host's instance
of the same buff grants the heal for a client's kill, so gating loses nothing (when the
host runs the mod). Fix template + sweep rule: `docs/BUG_CLASSES.md` section 29. Our fixed
sites: `career_tweaker_balance.lua:3489-3496`, `chaos_wastes_tweaker_dev.lua:12106-12116`.
Sweep any new proc for `heal_network(` / `add_damage_network(` without a gate.

### 4.2 Gated/ordered registration divergence - the #425/#426 axis (BUG_CLASSES 9 and 31 family)

Every buff RPC carries an int index into `NetworkLookup.buff_templates` (section 2.6).
`create_lookup` (`network_lookup.lua:38-47`) makes vanilla indices identical across peers
only because the same code builds them at boot. Mod appends therefore MUST be:

1. **Unconditional** - never behind a user toggle. Toggle-gated registration shifted every
   later index by one per absent entry; burned ct v0.7.59/v0.7.60/v0.7.66
   (`chaos_wastes_tweaker_dev.lua:10260-10268`) and pre-audit crt
   (`career_tweaker_balance.lua:6-34`). The toggle may gate only the CONTENT overlay
   (crt: stub -> real body swap, :16-30) or the roll-pool insert (ct:
   `_add_dormant_to_pool` :10343, pool is not networked :10257-10258).
2. **Deterministically ordered** - crt registers its 31 names alphabetically
   (`career_tweaker_balance.lua:40-74`, order marked load-bearing); bt's BR list is the
   same doctrine at 328-entry scale
   (`_archive/buff_tweaker_v0.1.12-alpha/.../buff_tweaker_registrations.lua:40-41`).
3. **Present on every peer** - this is the open gap. Ordering discipline inside one mod
   does not help a peer who lacks the mod (or loads mods in a different order - the
   cross-MOD append order follows VMF load order [unverified that VMF load order can
   differ per peer; treat as hostile]). Host sends `rpc_add_buff(N)`; the non-parity peer
   resolves N to a different name, or the strict `__index` throws
   ("Table buff_templates does not contain key", `network_lookup.lua:2360-2367`).
   That is issues #425 (crt) / #426 (ct): gameplay axes requiring the WS1.5 peer-parity
   gate (`docs/OOP_REFACTOR_PLAN.md:49-60`), NOT silent substitution - and per
   BUG_CLASSES 31, the eventual safety must never be gated on a feature toggle.

### 4.3 Strict NetworkLookup metatable - BUG_CLASSES 4

Any read of a missing key on ANY `NetworkLookup.*` table errors
(`network_lookup.lua:2360-2367`). Existence checks must be
`rawget(NetworkLookup.buff_templates, name)` (`career_tweaker_balance.lua:85-99`,
`chaos_wastes_tweaker_dev.lua:10197`).

### 4.4 Server-controlled buff constraints

- Durations are FORBIDDEN on server-controlled buffs - boot-time fassert
  (`buff_system.lua:259`).
- server_buff_ids are a finite pool; exceeding `NetworkConstants.server_controlled_buff_id.max`
  is a hard `ferror` (`buff_system.lua:219-233`). A proc/AoE loop that spam-adds
  server-controlled buffs can exhaust it (memory
  `reference_vt2_cw_boon_aoe_rpc_overflow_crash`).
- `add_buff` on a frozen unit returns nil (`buff_extension.lua:168-170`); code holding
  buff ids must nil-check before `remove_buff`.

### 4.5 Max-resource mutation - consumption-side doctrine

Never write `ext._max_overcharge` / `_max_energy` / any `_max_<resource>`: engine network
config caps fassert at per-frame update (memory
`feedback_vt2_max_resource_consumption_side`; burned ct v0.7.80-alpha and
v0.7.99-dev..v0.7.101-dev). The engine-idiomatic lever is the consumption-side stat buff:
`reduced_overcharge` (`buff_templates.lua:147`), `ammo_used_multiplier` (:28, read by
`PlayerUnitEnergyExtension.drain` [unverified line]), `reduced_overcharge_from_passive`
(:148, consumed at `damage_utils.lua:2208`). ct_meta_ammo is the compliant instance
(`chaos_wastes_tweaker_dev.lua:46, :236-250`). Registration-side vs consumption-side rule
of thumb: REGISTER names/templates unconditionally at load (wire safety);
MUTATE consumption math per-toggle at runtime (feature gating).

### 4.6 Boot-merge shadowing (runtime writes to source tables are dead)

`TalentBuffTemplates`, `OldTalentBuffTemplates`, `DeusPowerUpBuffTemplates`,
`WeaponTraits/WeaveTraits.buff_templates` are all merged INTO `BuffTemplates` at parse
time (`buff_templates.lua:9578-9587`, `morris_buff_settings.lua:7310`). Post-boot writes
must target `BuffTemplates` (and `NetworkLookup`) directly; write the source table too
only for introspection symmetry (`career_tweaker_big_rebalance.lua:170-175` doc note).

### 4.7 THP/heal-type semantics

`heal_from_proc` is NOT permanent - it lands in temp health
(`generic_status_extension.lua:2247` whitelist; `player_unit_health_extension.lua:873-877`).
A "green heal" boon must use a whitelisted type; ct picked `health_regen`
(`chaos_wastes_tweaker_dev.lua:12100-12114`) - which also does NOT clear wounded state
(`generic_status_extension.lua:2250-2252`), a semantic to confirm intended per feature.

### 4.8 Misc engine facts that bite

- `damage_amount` is quantized by `networkify_damage` (`damage_utils.lua:1672`) BEFORE
  procs and application - sub-quantum tweaks (< 1/64 [unverified exact quantum]) vanish.
- `on_damage_dealt` procs may rewrite damage via the modifiable table
  (`damage_utils.lua:1802-1809`) - a hook comparing pre/post values must account for it.
- THP degen and knockdown-bleed are excluded from statistics, rumble, telemetry and
  `on_damage_taken` procs (`player_unit_health_extension.lua:660, :674, :682, :702`);
  diagnostics counting "hits" should exclude them the same way.
- Proc param lists per event are fixed (`ProcEventParams`, `buff_templates.lua:300-303
  region`); custom procs get params positionally (`buff_extension.lua:1316-1323`).
- `BuffExtension.init` pre-creates a stat-buff bucket for every key in
  `StatBuffApplicationMethods` (:42-44) - a NEW custom stat_buff name must be added to
  `StatBuffApplicationMethods` BEFORE any BuffExtension inits (i.e. at mod load), or its
  `_stat_buffs[name]` bucket is nil and `apply_buffs_to_value` crashes (:1392 `pairs(nil)`).
  bt's BR list carried 3 such method registrations for exactly this reason
  (`buff_tweaker_registrations.lua:34-38`).

---

## 5. Implications for our mods - where we fight the engine

Ranked candidates; each names our code, the engine-idiomatic alternative, and the payoff.

1. **P0 - crt/ct networked buff names still lack a peer-parity gate (issues #425/#426).**
   `career_tweaker_balance.lua:83-103` and `chaos_wastes_tweaker_dev.lua:10192-10336`
   guarantee determinism only among peers running the same mods. A vanilla peer in the
   lobby still CTDs on the strict lookup when our int rides `rpc_add_buff`
   (`buff_system.lua:302-305` -> `network_lookup.lua:2360-2367`). Engine-idiomatic
   endpoint: buffs whose only consumer is the owner should never enter the wire at all -
   apply them via `BuffExtension.add_buff` locally (no `BuffSystem.add_buff`) so no
   lookup int is sent; buffs that MUST sync go behind the WS1.5 `all_peers_have(mod_id)`
   gate (`docs/OOP_REFACTOR_PLAN.md:55-60`), never behind silent substitution and never
   toggle-coupled (BUG_CLASSES 31).

2. **P1 - crt armor/overcharge shims monkey-patch live extension methods per call.**
   `career_tweaker_armor_overcharge.lua:237-240` (replace `be.has_buff_type`), :253-256
   (replace `be.apply_buffs_to_value`), :299-302 (replace `be.trigger_procs`, which
   swallows EVERY `on_damage_taken` proc for that tick - self-documented at :294-296).
   Narrower engine seam for the trigger_procs case: the proc body is resolved by name
   from the writable global `ProcFunctions` at fire time (`buff_extension.lua:1351`) -
   wrap ONLY the Cursed Armor counter's proc function once at load (gate inside on the
   per-tick exemption flag) instead of disabling the whole event dispatch. The
   `apply_buffs_to_value` shim is defensible (vanilla's exemption sets are file-locals,
   `damage_utils.lua:2109-2132`, unreachable), but should filter to exactly
   `"damage_taken_to_overcharge"` as it does today - keep it.

3. **P1 - ct meta-boon stacks are local-only buffs feeding a server-computed stat.**
   `_make_meta_proc` adds stacks via local `buff_extension:add_buff(stack_name)`
   (`chaos_wastes_tweaker_dev.lua:11136-11138`). For attacker-side stats (crit, ammo)
   the consumption site is the owner's machine, so local-only is correct and wire-silent
   (good). But `ct_meta_health` rides the `max_health` stat buff, and max health is
   recomputed ON THE SERVER each tick (`player_unit_health_extension.lua:310-319`) from
   the server's copy of the unit's buff extension - a client's local-only stacks are
   invisible to a host that lacks ct (silent no-op) and only work today because the boon
   proc fires on every ct-running peer. Engine-idiomatic: keep local adds for
   attacker-consumed stats; route health/defensive stats through
   `BuffSystem.add_buff_synced` (`buff_system.lua:849`) once the #426 parity gate exists,
   or document the "all peers must run ct" requirement on the toggle.

4. **P1 - dead Big Rebalance code shipping in crt.**
   `career_tweaker_big_rebalance.lua:32` early-returns above ~2,700 inert lines (same
   pattern in et/wt per `docs/OOP_REFACTOR_PLAN.md:116-118`). Pending user decision
   (#433) - do not delete unilaterally; if BR revives, the registration list must come
   back as ONE shared sorted list (the bt pattern,
   `buff_tweaker_registrations.lua:1-42`), not per-mod copies.

5. **P2 - crt talent reworks mutate shared templates where per-application params exist.**
   The patch engine writes `BuffTemplates[buff].buffs[1][field]` globally
   (`career_tweaker_balance.lua:112-121`). For vanilla-applied talent buffs this is the
   only lever (vanilla add sites pass no params) - fine. But for buffs crt's OWN procs
   add, the engine's `params.external_optional_*` channel
   (`buff_extension.lua:240-251`) achieves per-instance values with zero restore
   bookkeeping and no cross-career bleed (memory
   `reference_wt_shared_template_global_mutation_breaks_native`). Prefer it in new
   crt proc code.

6. **P2 - crt stub template shape diverges from the engine-validated stub.**
   `career_tweaker_balance.lua:36-38` uses `{ buffs = {}, _crt_pending = true }` (zero
   sub-buffs: `add_buff` returns `sub_buffs_added = 0`, skips `_buff_id_refs` :493-498);
   the BR stub used one no-op stat buff (`career_tweaker_big_rebalance.lua:62-73`),
   which exercises the normal add/remove path. Zero-sub-buff templates are accepted by
   `add_buff` (loop :184 simply doesn't run) but produce ids with no `_buff_id_refs`
   entry - if any future code calls `num_sub_buffs`/`remove_buff` on such an id, verify
   the nil-ref path (`buff_extension.lua:861, :889`) before relying on it. Cheap
   hardening: adopt the one-no-op-stat-buff stub shape in `_crt_make_stub`.

7. **P2 - ct kill-heal semantics vs wounded state.**
   `chaos_wastes_tweaker_dev.lua:12114` uses `health_regen` for a permanent heal;
   `heal_can_remove_wounded` excludes it (`generic_status_extension.lua:2251`), so the
   boon can fill green health while the wounded (death-on-next-down) flag stays set.
   Confirm intended behavior with the user (doctrine
   `feedback_confirm_intended_behavior_before_fixing`); if wounded-clear is wanted at
   full heal, vanilla's channel is `StatusUtils.set_wounded_network`
   (`damage_utils.lua:2546`), server-side.

8. **P2 - custom stat-buff names must pre-seed StatBuffApplicationMethods.**
   No current crt/ct entry adds a NEW stat_buff key [unverified - sweep pending], but the
   BR revival will (bt list carried 3, `buff_tweaker_registrations.lua:34-38`). The
   bucket table is snapshotted per unit at `BuffExtension.init`
   (`buff_extension.lua:42-44`); registration therefore belongs with the other
   unconditional load-time registrations, and (like stat-buff methods in bt) needs NO
   NetworkLookup entry.
