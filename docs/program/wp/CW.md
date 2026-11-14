# Track CW: Chaos Wastes, Events and Enemies work packages

Source audit: `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/A4.md` (finding ids A4-Fnn). Cards are ordered by priority. Each card stands alone. Path aliases are redefined inside every card that uses them.

## Family brief

- What it is: four VMF mods. `chaos_wastes_tweaker_dev/` (mod id `ct_dev`, `0.7.354-dev`, friends-only, 94 Lua files) and `chaos_wastes_tweaker/` (mod id `ct`, `0.7.354-beta`, public) reshape Chaos Wastes runs: boons, curses, chests, coins, Adventure maps in the run graph. `event_tweaker/` (mod id `event_tweaker`, `0.4.54-dev`) injects mutators through the live-event backend. `enemy_tweaker/` (mod id `enemy_tweaker`, `0.7.65-dev`) changes spawns and adds two custom breeds.
- Entry files: `<tree>/scripts/mods/<tree>/<tree>.lua`, plus `<tree>_data.lua` (option widgets) and `<tree>_localization.lua`. Offline tests: `qa/lua/tests/test_ct_*.lua`, `ct_*.lua`, `test_event_*.lua`, `test_et_*.lua`, `test_peer_parity_transition.lua`. Run them with `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1`. A new `test_*.lua` file must be added to the `suites` list in `qa/lua/run.lua` or the gate fails.
- The two Chaos Wastes trees are diverged forks, not a snapshot plus a delta. Dev holds: a 1,597-line manifest entry, 57 modules that public lacks (all `_ct_*_owner.lua`, the journey-stat crash guard, the flow-state cap guard, replacement compensation, diagnostics). Public holds: a 13,294-line monolith entry and 12 files that dev lacks: the complete #426 wire fence (`_ct_wire_runtime.lua`, `_ct_wire_bootstrap.lua`, 22 `register_hook` sites at `_ct_peer_parity_owner.lua:739-1115`), `_lib_network_lookup.lua`, eight `_ct_official_*.lua`, `_ct_diag_official_apply_evidence.lua`, and the `/verify_ct_*` commands. Never copy a whole file or tree across. "Streams: both" means: make the same logical change by hand in each tree.
- Trap 1, base-class hooks do not reach subclasses. Vanilla `class()` copies parent methods into the child table when the child is defined (`Vermintide-2-Source-Code/foundation/scripts/util/class.lua:53-59`). A hook on `GameModeBase.x` never fires for a `GameModeAdventure` instance. Hook the derived class.
- Trap 2, the boon roller. `DeusPowerUpRarityPool` is read once at boot. Rolls read `DeusPowerUpsArrayByRarity` and `DeusPowerUpsArray` (`Vermintide-2-Source-Code/scripts/helpers/deus_power_up_utils.lua:138-146`). Never remove a row from `DeusPowerUpsLookup` or from any `NetworkLookup` table: the numeric index is what travels on the wire and must be the same on every peer. Register unconditionally at load, gate at roll, grant and purchase.
- Trap 3, proof of "this player has the mod" arrives late. The parity beacon rides VMF messages. VMF pings a peer only from its `PlayerManager.add_remote_player` hook and forgets the peer in `remove_player` (`<repos>/Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/network.lua:366-373,375-397`; local clone, commit `81bb4ce`). Vanilla calls `hot_join_sync` before `add_remote_player` (`Vermintide-2-Source-Code/scripts/network/peer_states.lua:432,450`) and removes every remote player at each level exit (`Vermintide-2-Source-Code/scripts/managers/player/player_manager.lua:170-175`). So a first-time joiner can never be proven before native sync, and a returning player is proven only by an acknowledgement kept from the previous level.
- Trap 4, VMF fails silently. A second `mod:hook` on the same (Class, method) from the same mod is dropped. `mod:dofile` re-runs the file on every call and returns nothing when the file errors. After any edit a boot must still print the mod's `[..:LOAD]` line.
- Trap 5, the tests and ratchets pin the current shape. Many offline tests assert literal source strings and dofile order; some pin a defect (WP-CW-01). `qa/check_file_sizes.ps1` fails when a file crosses 1,500 non-empty lines or a frozen file grows: the dev entry is at about 1,497, the public entry is frozen at 12,710 (`qa/baselines/file_sizes.json`). Put new code in modules, not in the entries. Load only one Chaos Wastes tree per rig boot: both register the same chat commands and share global names.
- House rule that applies to every card: each code change bumps `MOD_VERSION` in the entry file and adds a `CHANGELOG.md` entry. Cards end at merged source and green acceptance. Publication follows `PROJECT_STANDARDS.md` section 6.6 and is not part of any card here.

### WP-CW-01 Make the Events curse join lock reach live game modes

| Field | Value |
|---|---|
| Priority | P0 (crash class for a joining player) |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | #430, #413 (advances both; the two-client crash proof stays class C) |
| Source | A4-F03 |
| Streams | `event_tweaker/` only (single stream) |

**Goal.** While a managed curse or the Shadow adapter is requested or active, `is_joinable()` on the live game-mode instance returns false in Adventure, Chaos Wastes (mission and map) and Weave.

**Context.** EVT = `event_tweaker/scripts/mods/event_tweaker/`.
- `EVT/_evt_guard430_curse_parity.lua:130-135` installs the lock as `mod:hook("GameModeBase", "is_joinable", ...)`. The lock state is the file-local `_curse_session_locked` (`:78-88`).
- Vanilla copies `GameModeBase.is_joinable` into every subclass at class definition (`Vermintide-2-Source-Code/foundation/scripts/util/class.lua:53-59`; `GameModeAdventure = class(GameModeAdventure, GameModeBase)` at `Vermintide-2-Source-Code/scripts/managers/game_mode/game_modes/game_mode_adventure.lua:8`). Only `GameModeInnVs` defines its own (`game_mode_inn_vs.lua:344`).
- The only caller uses the instance: `game_mode:is_joinable()` (`Vermintide-2-Source-Code/scripts/network/peer_states.lua:114-116`). So the hook never runs and the session stays joinable.
- The lock is what keeps a player without the curse packages out of a mission that already runs a managed curse (`EVT/event_tweaker_curses.lua` `MANAGED_CURSES`, 11 ids).
- The offline test pins the defect: `qa/lua/tests/test_event_curse_join_policy.lua:55-56` asserts the source contains `mod:hook("GameModeBase", "is_joinable"`.

**Steps.**
1. Test first. Create `qa/lua/tests/test_event_join_lock_reach.lua` and add `"test_event_join_lock_reach"` to the `suites` list in `qa/lua/run.lua`. The file returns `function(H, repo_root)`. Load the policy with `loadfile(repo_root .. "/event_tweaker/scripts/mods/event_tweaker/event_tweaker_curse_join_policy.lua")()`. Build a class model that copies like vanilla: `local function class(parent) local c = {}; c.__index = c; for k, v in pairs(parent or {}) do if k ~= "__index" then c[k] = v end end; return c end`. Create `env.GameModeBase = class()` with `is_joinable = function() return true end`, then `env.GameModeAdventure`, `env.GameModeDeus`, `env.GameModeMapDeus`, `env.GameModeWeave` with `class(env.GameModeBase)`. Stub hook: `local function hook(class_name, method, handler) local t = env[class_name]; local orig = t[method]; t[method] = function(self, ...) return handler(orig, self, ...) end end`. Cases with `H.test`: (a) `Policy.JOIN_LOCK_CLASSES` has exactly those four names and not `"GameModeBase"`; (b) after `Policy.install_join_lock(hook, function() return locked end)`, for each name `setmetatable({}, env[name]):is_joinable()` is `false` when `locked = true` and `true` when `locked = false`; (c) a control: hooking only `GameModeBase` in a fresh env leaves `setmetatable({}, env.GameModeAdventure):is_joinable()` equal to `true`. Cases (a) and (b) fail before step 2.
2. In `EVT/event_tweaker_curse_join_policy.lua` add `M.JOIN_LOCK_CLASSES = { "GameModeAdventure", "GameModeDeus", "GameModeMapDeus", "GameModeWeave" }` and `function M.install_join_lock(hook, is_locked)` that, for each name, calls `hook(name, "is_joinable", function(func, self, ...) return M.allow_join(func(self, ...), is_locked()) end)` and returns the number of hooks requested. Keep `M.allow_join` unchanged.
3. In `EVT/_evt_guard430_curse_parity.lua` replace lines 130-135 with: `JoinPolicy.install_join_lock(function(class_name, method, handler) if rawget(_G, class_name) then mod:hook(class_name, method, handler) else pcall(printf, "[et:430] join lock class missing: %s", tostring(class_name)) end end, function() return _curse_session_locked end)`.
4. In the same file add `rt_register("issue430_join_lock_reaches_instances", function() ... end)`: for each name in `JoinPolicy.JOIN_LOCK_CLASSES`, read `local cls = rawget(_G, name)`; return an error string if it is missing; save `_curse_session_locked`, set it to `true`, call `local ok, res = pcall(cls.is_joinable, {})`, restore the saved value; return `name .. " not locked"` unless `ok and res == false`. Then repeat with the flag `false` and require `res == true`.
5. In `qa/lua/tests/test_event_curse_join_policy.lua` replace the two assertions at lines 55-56 with one: the guard source contains `JoinPolicy.install_join_lock(`.
6. Update the hook list in `event_tweaker/CLAUDE.md` ("One hook per (Class, method)" paragraph) and the matching row in `event_tweaker/ENGINE_SURFACE.md`. Bump `MOD_VERSION` in `EVT/event_tweaker.lua:4` and add a `CHANGELOG.md` entry.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 and lists the three new cases. `git grep -n 'mod:hook("GameModeBase"' -- event_tweaker` prints nothing.
- RIG: add `qa/runtime/event_tweaker/issue_430_join_lock.lua`, arena `mission:military`, mods `{ "event_tweaker" }`, plan option `mut_curse_blood_storm = true` (must be set before the mission loads). In `run(T)`: `T.require(Managers.state.game_mode._mutator_handler._active_mutators["curse_blood_storm"] ~= nil, "managed curse active")` (INCONCLUSIVE without the `morris` DLC); `T.expect_eq(Managers.state.game_mode:game_mode():is_joinable(), false, "session locked")`; `T.expect_rt("event_tweaker", "issue430_join_lock_reaches_instances")`. `host_expect_log = { "%[et:430%] peer%-required session hot%-join contract LOCKED" }`. A second case in the same folder without the option expects `is_joinable() == true`.
- Evidence class: U and R close finding A4-F03. #430 and #413 are advanced; a late join by a player without the mod is class C.

**Guardrails.** Do not hook `GameModeBase` or `GameModeManager.is_joinable` (nothing calls the manager method for joins). Do not change `can_arm`, `has_pending_remote` or the beacon. Do not edit `EVT/_lib_peer_parity.lua`: it is a synced copy of `tools/shared_lib/_lib_peer_parity.lua`. Do not try to make curses arm in a full lobby here; whether `can_arm` is ever true while remote players are still loading is a separate open question.

**Stop and escalate if.** Another `event_tweaker` module already hooks `is_joinable` on any of the four classes (VMF would drop the second hook). The rig case shows the curse active but `is_joinable()` still true after the fix.

### WP-CW-02 Port the journey-stat crash guard to public Chaos Wastes

| Field | Value |
|---|---|
| Priority | P0 (crash when a public-mod player wins a journey at Cataclysm 2 or 3) |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | none open (the dev fix was made under #291) |
| Source | A4-F22 |
| Streams | `chaos_wastes_tweaker/` only. Dev already has the guard |

**Goal.** In the public mod, finishing a journey on a difficulty outside the default list records the highest default difficulty instead of raising a Lua error.

**Context.** CTD = `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/`, CTP = `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/`.
- Vanilla `StatisticsUtil._register_completed_journey_difficulty` computes `difficulty_index = table.find(difficulties, difficulty_name)` and then evaluates `current_completed_difficulty < difficulty_index` (`Vermintide-2-Source-Code/scripts/managers/backend/statistics_util.lua:1051-1054`). `cataclysm_2` and `cataclysm_3` are not in the default list, so the index is nil and the comparison throws.
- Dev clamps the recorded difficulty in `CTD/_ct_journey_difficulty_guard.lua:37-48` and loads it at `CTD/_ct_run_creation_owner.lua:262`.
- Public has the difficulty ramp (`CTP/_ct_progressive_difficulty.lua:5-8`, used by `CTP/_ct_official_verify_runtime.lua:130-147`) and the Single Mission Loader difficulties (`CTP/_ct_dev_mission_catalog.lua:65`), but no hook on that function: `git grep -n "_register_completed_journey_difficulty" -- chaos_wastes_tweaker` prints nothing.
- The public package lists `scripts/mods/chaos_wastes_tweaker/*`, so a new file ships without a package edit (`chaos_wastes_tweaker/resource_packages/chaos_wastes_tweaker/chaos_wastes_tweaker.package`).

**Steps.**
1. Test first. Create `qa/lua/tests/test_ct_journey_guard_both_trees.lua` and register it in `qa/lua/run.lua`. For each of the two directories CTD and CTP: `local installer = assert(loadfile(dir .. "_ct_journey_difficulty_guard.lua"))()`; call `installer(stub_mod)` where `stub_mod.hook = function(_, class_name, method, fn) captured = fn end`. Before the call set globals `printf = function() end`, `table.find = function(t, v) for i = 1, #t do if t[i] == v then return i end end end`, and `Managers = { state = { difficulty = { get_default_difficulties = function() return { "normal", "hard", "harder", "hardest", "cataclysm" } end } } }`; restore them after. Assert: `captured(func, db, player, "journey_citadel", "khorne", "cataclysm_3")` calls `func` with fifth argument `"cataclysm"`; with `"hardest"` the argument is unchanged. The CTP half fails before step 2 because the file does not exist.
2. Copy `CTD/_ct_journey_difficulty_guard.lua` to `CTP/_ct_journey_difficulty_guard.lua`. Change only the header comment line "Owned by" to name `chaos_wastes_tweaker.lua`.
3. In `CTP/chaos_wastes_tweaker.lua`, immediately above the line `mod:hook("DeusPowerUpUtils", "generate_random_power_ups", function(func, ...)` (currently `:2471`), add one top-level statement: `mod:dofile("scripts/mods/chaos_wastes_tweaker/_ct_journey_difficulty_guard")(mod)`.
4. The public entry is size-frozen. Remove one comment-only line elsewhere in the same file so its non-empty line count does not grow.
5. Bump `MOD_VERSION` at `CTP/chaos_wastes_tweaker.lua:44` and add a `chaos_wastes_tweaker/CHANGELOG.md` entry.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the new cases. `pwsh -NoProfile -File qa/check_file_sizes.ps1` does not exit 2. `git grep -c "_register_completed_journey_difficulty" -- chaos_wastes_tweaker/scripts` is at least 1.
- RIG: add `qa/runtime/ct/wp_cw_02_journey_guard.lua` (no open issue number, so the file is named after the card), arena `keep`, mods `{ "ct" }`. Build `db = { get_persistent_stat = function() return 99 end, set_stat = function() error("unexpected stat write") end }` and `player = { stats_id = function() return "rig" end, profile_index = function() return 1 end }`. `local ok, err = pcall(StatisticsUtil._register_completed_journey_difficulty, db, player, "journey_citadel", "khorne", "cataclysm_3")`; `T.expect(ok, "no nil comparison: " .. tostring(err))`. With 99 as the stored value the vanilla body writes nothing (`statistics_util.lua:1054-1076`). Run the same file with mods `{ "ct_dev" }` as a control.
- Evidence class: U and R close finding A4-F22.

**Guardrails.** Do not port anything else from dev in this card. Do not change the ramp. Do not add a second hook on this function if one appears later in the public tree.

**Stop and escalate if.** `:2471` is no longer a top-level statement (inside a function or `do` block). The size gate fails after step 4.

### WP-CW-03 Make custom boon rolls and purchases obey toggles and parity

| Field | Value |
|---|---|
| Priority | P0 (a custom boon can reach a peer without the catalog: #426 crash class) |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | #426, #1191 (advances both; the mixed-lobby proof stays class C) |
| Source | A4-F02 |
| Streams | both. Dev needs all steps. Public already strips by parity at roll time and filters purchases; it needs only the toggle part (step 7) |

**Goal.** A custom boon is offered by a roll only when its enable toggle is on and peer parity is confirmed, and a shrine purchase of a custom boon is refused while parity is not confirmed.

**Context.** CTD = `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/`, CTP = `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/`.
- The vanilla roller reads `DeusPowerUpsArrayByRarity[rarity] or DeusPowerUpsArray` (`Vermintide-2-Source-Code/scripts/helpers/deus_power_up_utils.lua:138-146`). `DeusPowerUpRarityPool` is read once at boot (`Vermintide-2-Source-Code/scripts/settings/dlcs/morris/deus_power_up_settings.lua:7121`).
- `inject_dormant_boon` inserts every custom boon into both arrays at load (`CTD/_ct_boon_registry.lua:255-259`). The toggle path and the #426 eject only edit `DeusPowerUpRarityPool` and the file-local set `_added_to_pool` (`CTD/_ct_boon_registry.lua:273-322`, `CTD/_ct_meta_trait_boons.lua:180-190`, `CTD/_ct_peer_parity_owner.lua:364-385`). So neither affects a roll. The mod's own changelog calls the array "never-ejected" (`chaos_wastes_tweaker_dev/CHANGELOG.md:1923`).
- The roll hook strips names for the duration of the vanilla call and restores them (`CTD/_ct_run_creation_owner.lua:575-630`), but `_should_strip` only knows disabled boons, bomb exclusivity and altar repeats.
- Shrine purchases skip `add_power_ups`. The `_try_buy_power_up` hook passes the purchase to vanilla with no parity test (`CTD/_ct_boon_grant_owner.lua:460-477`); vanilla writes it into synchronized run state (`Vermintide-2-Source-Code/scripts/managers/game_mode/mechanisms/deus_run_controller.lua:1725-1768`), which encodes the boon as a lookup integer (`Vermintide-2-Source-Code/scripts/managers/game_mode/mechanisms/deus_run_state_spec.lua:60`). Vanilla copes with a refused purchase on both sides (`deus_run_controller.lua:989-1004`, `:1058-1077`).
- `_added_to_pool[name]` is already the right truth: it is set only when the toggle allows it and parity holds, and cleared on eject.

**Steps.**
1. Test first, policy. In `qa/lua/tests/test_ct_426_exact_catalog.lua` (it already loads `CTD/_ct_wire_policy.lua`) add cases for a new pure function `rollable(is_modded, in_pool, exact_safe)`: `(false, false, false)` is true; `(true, true, true)` is true; `(true, false, true)` is false; `(true, true, false)` is false. Add cases for the existing `purchase_allowed(name, exact_safe)`: `("ct_meta_health", false)` is false, `("ct_meta_health", true)` is true, `("deus_reckless_swings", false)` is true.
2. Test first, roll hook. In `qa/lua/tests/test_ct_run_creation_owner.lua` add a case next to the existing ones that call `f.hooks["DeusPowerUpUtils.generate_random_power_ups"]` (around `:485-630`): put `{ name = "ct_boon_vauls_anvil", rarity = "unique" }` into the fixture's `DeusPowerUpsArray` and `DeusPowerUpsArrayByRarity.unique`, set `mod._ct_boon_rollable = function(name) return name ~= "ct_boon_vauls_anvil" end`, call the hook with a stub `func` that records every name present in both arrays during the call. Assert the name is absent during the call and present again afterwards, and that both array lengths are unchanged.
3. In `CTD/_ct_wire_policy.lua` add `function M.rollable(is_modded, in_pool, exact_safe) return is_modded ~= true or (in_pool == true and exact_safe == true) end`.
4. In `CTD/_ct_boon_registry.lua`, directly after `_remove_dormant_from_pool` (ends `:322`), publish `mod._ct_boon_rollable = function(name) local modded = _injected_dormants[name] ~= nil; local policy = mod._ct_wire_policy; if not policy then return not modded end; local safe = mod._ct_wire_safe ~= nil and mod._ct_wire_safe() == true; return policy.rollable(modded, _added_to_pool[name] == true, safe) end`.
5. In `CTD/_ct_run_creation_owner.lua` `_should_strip` (`:575`), add as the first test after the nil check: `if mod._ct_boon_rollable and not mod._ct_boon_rollable(name) then return true end`. In `CTD/_ct_boon_grant_owner.lua` `mod._ct_bot_pick_random_for_rarity` (`:178-193`) add the same predicate to the eligibility condition.
6. In `CTD/_ct_boon_grant_owner.lua`, first statements of the `_try_buy_power_up` hook (`:460`): `local pu_name = power_up and power_up.name; if pu_name and mod._ct_wire_policy and not mod._ct_wire_policy.purchase_allowed(pu_name, mod._ct_wire_safe ~= nil and mod._ct_wire_safe() == true) then pcall(printf, "[ct:426] BLOCKED modded boon at purchase: %s (peer parity not confirmed)", tostring(pu_name)); return false end`.
7. Public toggle part. In `CTP/chaos_wastes_tweaker.lua`, after `_remove_dormant_from_pool` (starts `:9078`) publish `mod._ct_boon_in_pool = function(name) return _added_to_pool[name] == true end`. In `_should_strip` (`:2595`), after the existing `_ct_power_up_wire_allowed` test add: `if mod._ct_is_modded_power_up and mod._ct_is_modded_power_up(name) and mod._ct_boon_in_pool and not mod._ct_boon_in_pool(name) then return true end`. Keep the public entry's non-empty line count from growing (remove comment-only lines).
8. Bump both `MOD_VERSION` values and add both changelog entries.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the new cases. `pwsh -NoProfile -File qa/check_file_sizes.ps1` does not exit 2.
- RIG: add `qa/runtime/ct_dev/issue_426_roll_gate.lua`, arena `keep`, mods `{ "ct_dev" }`; run the same file with mods `{ "ct" }` for step 7. Steps: `T.set` `enable_boon_reworks` to true and every other `enable_boon_*` option to false (`enable_boon_vauls_anvil`, `enable_boon_manann_tempest`, `enable_boon_taal_twinned_arrow`, `enable_boon_asuryan_wrath`, and in dev `enable_boon_anath_raema_swiftness`); `T.wait(3)`; record `#DeusPowerUpsArray`; call `DeusPowerUpUtils.generate_random_power_ups(seed, 4, {}, "hardest", 0.5, DeusPowerUpAvailabilityTypes.shrine, "es_mercenary", "unique")` for 500 seeds (signature at `deus_power_up_utils.lua:391`; the second return value is the list); `T.expect` no returned name starts with `ct_boon_`; `T.expect_eq(#DeusPowerUpsArray, recorded, "arrays restored")`. Then `T.set("ct_dev", "enable_boon_vauls_anvil", true)`, `T.wait(3)`, 2,000 seeds, `T.expect` that `ct_boon_vauls_anvil` appears at least once.
- RIG, purchase gate (dev): `qa/runtime/ct_dev/issue_426_purchase_gate.lua`, arena `deus`. `local m = get_mod("ct_dev")`; save `m._ct_wire_safe`, replace it with `function() return false end`; `local rc = Managers.mechanism:game_mechanism():get_deus_run_controller()`; `local pu = DeusPowerUpUtils.generate_specific_power_up("ct_meta_health", "exotic")`; `T.expect_eq(rc:_try_buy_power_up(rc:get_own_peer_id(), pu, 0), false, "purchase refused")`; `T.expect` that `rc:get_player_power_ups(rc:get_own_peer_id(), 1)` contains no `ct_meta_health`; restore `m._ct_wire_safe`. `host_expect_log = { "%[ct:426%] BLOCKED modded boon at purchase: ct_meta_health" }`.
- Evidence class: U and R close finding A4-F02. #426 and #1191 keep their class C part.

**Guardrails.** Do not remove rows from `DeusPowerUpsArray`, `DeusPowerUpsArrayByRarity`, `DeusPowerUpsLookup`, `DeusPowerUps` or any `NetworkLookup` table: only strip inside the existing remove-then-restore window. Do not change `_ct_wire_policy` row counts or the identity string. Do not add lines to `CTD/chaos_wastes_tweaker_dev.lua` (size ratchet).

**Stop and escalate if.** The 2,000-seed positive check never returns `ct_boon_vauls_anvil` (the boon is being stripped somewhere else, or `_added_to_pool` is not set in solo). A third roll path is found that does not go through `DeusPowerUpUtils.generate_random_power_ups`.

### WP-CW-04 Keep custom boons across level changes and joins

| Field | Value |
|---|---|
| Priority | P0 (purchased boons are deleted for the whole party in co-op) |
| Size | M. Part A is S and can ship alone |
| Agent | strong for part B: it edits synchronized run state and must reason about ordering. Part A: any |
| Depends on | none |
| Issues | #426 (advances), #144, #288 (may explain "boon stops working" reports; do not close on this card) |
| Source | A4-F04 |
| Streams | Part A both. Part B `chaos_wastes_tweaker_dev/` only: the public fence strips at five different hooks (`chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/_ct_peer_parity_owner.lua:971-1114`) and receives part B through WP-CW-10 stage 2 instead of a hand port into the monolith |

**Goal.** A player who was proven to run the mod stays proven across a level load, and custom boons removed for an unproven joiner come back automatically once every player is proven.

**Context.** CTD = `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/`, CTP = `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/`.
- The dev hot-join fence runs inside `GameNetworkManager.hot_join_sync`. If `inst:peer_has(peer_id)` is false it calls `_ct_strip_modded_content`, which deletes every player's custom power-ups, party power-ups, persistent buffs and live buffs (`CTD/_ct_peer_parity_owner.lua:777-820`, strip at `:447-515`).
- Proof cannot arrive before that call for a first-time joiner (family brief, trap 3). For a returning player the proof is the acknowledgement kept from the previous level, and the shared library forgets it after 15 s off the roster: `ABSENCE_GRACE = opts.absence_grace or 15.0` (`tools/shared_lib/_lib_peer_parity.lua:170`, expiry at `:705-712`). Every level exit removes all remote players (`Vermintide-2-Source-Code/scripts/managers/player/player_manager.lua:170-175`). Static evidence: a load longer than 15 s strips the party at the next level.
- Both trees already forget a peer on real disconnect through a `GameNetworkManager.remove_peer` hook (`CTD/_ct_peer_parity_owner.lua:827-833`, `CTP/_ct_peer_parity_owner.lua:1115-1130`), so a long grace is safe.
- The gate's `on_enable` callback runs when every peer is proven again (`CTD/_ct_peer_parity_owner.lua:749-755`).

**Steps.**
1. Part A, test first. In `qa/lua/tests/test_peer_parity_transition.lua` add a case using the file's existing helpers (`build_inst(factory)` at `:23`; give it an optional options argument): build an instance with `{ absence_grace = 600, poll_interval = 0.5 }` and a stub `Managers.player.human_players` the test can change; acknowledge peer `"p1"`; tick once with `"p1"` on the roster; remove `"p1"`; tick 60 s in 0.5 s steps; assert `inst:peer_has("p1")` is true; call `inst:forget_peer("p1")`; assert false. Add the control with default options: after 16 s off the roster `peer_has` is false. In `qa/lua/tests/test_ct_boon_split.lua`, next to `H.equal(options.channel, "ct_boon_catalog_exact_v1")` (`:136`), add `H.equal(options.absence_grace, 600)`.
2. Part A, fix. Add `absence_grace = 600,` to the factory options table at `CTD/_ct_peer_parity_owner.lua:280-286` and at `CTP/_ct_peer_parity_owner.lua:199-206`. Do not edit the library.
3. Part B, test first. `qa/lua/tests/test_ct_boon_split.lua` already installs the dev parity owner with a fake factory. Add cases: (a) with a fake `run_state` holding one vanilla and one custom power-up row for one player (use the nested shape `_ct_each_server_state_row` walks, `CTD/_ct_peer_parity_owner.lua:422-445`), `mod._ct_strip_modded_content("test")` leaves the vanilla row and `mod._ct_stripped_stash_size()` returns 1; (b) calling the registered gated feature's `on_enable` puts the custom row back after the vanilla row and the stash size is 0; (c) calling `on_enable` twice does not duplicate the row; (d) advancing the owner's update by more than 120 s without `on_enable` empties the stash and prints one `[ct:426] stash expired` line.
4. Part B, fix in `CTD/_ct_peer_parity_owner.lua`. Make `_ct_filter_wire_entries` return the removed entries as a third value. In `_ct_strip_modded_content`, for each row passed to `set_player_power_ups` and `set_player_persistent_buffs`, and for the party list, append `{ kind, peer_id, local_player_id, profile_index, career_index, entries }` to a file-local `_stash` and set `_stash_deadline = _clock + 120`. Add `_ct_restore_stash()`: server only; for each stash row read the current list with the matching getter, append entries that are not already present (compare `client_id` for power-ups, the name for persistent buffs), write it back with the matching setter; clear the stash. Call it from `gated_feature_spec.on_enable` after `_ct_inject_modded_pools()`. In `owner_update` drop the stash after the deadline. Publish `_ct_restore_stripped_content` and `_ct_stripped_stash_size` through the `PUBLIC_FIELDS` list (`:61-78`) so the rig can call them.
5. Bump versions and changelogs. State in the dev changelog that live buffs of a restored boon return at the next spawn, not instantly.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the new cases.
- RIG: add `qa/runtime/ct_dev/issue_426_strip_restore.lua`, arena `deus`, mods `{ "ct_dev" }`. `local m = get_mod("ct_dev")`; `local rc = Managers.mechanism:game_mechanism():get_deus_run_controller()`; `rc:add_power_ups({ DeusPowerUpUtils.generate_specific_power_up("ct_meta_health", "exotic") }, 1, false)`; `T.wait_until` the name is in `rc:get_player_power_ups(rc:get_own_peer_id(), 1)`; `m._ct_strip_modded_content("rig")`; `T.expect` the name is gone and `m._ct_stripped_stash_size() >= 1`; `m._ct_restore_stripped_content()`; `T.expect` the name is back exactly once and the stash size is 0.
- Evidence class: U closes part A of finding A4-F04; U and R close part B for solo state. The real join and the real level change are class C.

**Guardrails.** Never restore while `mod._ct_wire_safe()` is false. Do not change `STRIP_GRACE`, the kick fallback or the order "strip before native sync". Do not edit `tools/shared_lib/_lib_peer_parity.lua` or its copies. Do not try to hold the joiner until proof arrives: it cannot arrive before sync (family brief, trap 3).

**Stop and escalate if.** `remove_peer` turns out not to run when a player disconnects (then a long grace is unsafe). Restoring a row makes a vanilla assertion fire in `DeusRunState`. Owner decision D-CW-03 (refund instead of restore) is answered differently from the default.

### WP-CW-05 Build vanilla run graph when any player lacks the mod

| Field | Value |
|---|---|
| Priority | P0 (map desync, and a level-load failure for the player without the mod) |
| Size | L. Split: part A gate policy and dev tree; part B public tree; part C join diagnostics |
| Agent | strong: the change decides which graph every peer builds, and a wrong default desyncs all-mod lobbies |
| Depends on | none |
| Issues | none open (wrong-map reports were tracked under closed #136) |
| Source | A4-F01 |
| Streams | both for parts A and B (the hash shim and the graph hook exist in both); part C dev only |

**Goal.** When the lobby contains a player who is not proven to run Tweaker: Chaos Wastes, every peer with the mod builds the unmodified vanilla run graph from the vanilla mission pool; otherwise behaviour is unchanged.

**Context.** CTD = `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/`, CTP = `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/`.
- Vanilla puts `#NetworkLookup.level_keys` into the lobby hash (`Vermintide-2-Source-Code/scripts/network/lobby_aux.lua:26`). Both trees append 6 keys per Adventure mission at boot and hook `LobbyAux.create_network_hash` to hide them (`CTD/chaos_wastes_tweaker_dev.lua:616-637`, `CTP/chaos_wastes_tweaker.lua:457-458`). Result: players with and without the mod can share a lobby. Removing the shim would lock mod users out of every lobby without the mod, so the shim stays (decision D-CW-01).
- The run graph is computed on every peer from a seed by the global `deus_populate_graph` (`Vermintide-2-Source-Code/scripts/managers/game_mode/mechanisms/deus_populate_graph.lua:965`). The mod's hook changes the inputs: curse count, dominant god, curse lists, shrine-to-mission conversion, Citadel gods (`CTD/_ct_campaign_graph_owner.lua:284-478`, `CTP/chaos_wastes_tweaker.lua:5622`). The mission pool is changed earlier by `AdventurePool.inject_pool()` (`CTD/_adventure_pool.lua:1013`), which keeps a vanilla snapshot (`take_snapshot` `:683`, `reset_to_snapshot` `:703`; public `:501`, `:521`).
- A peer without the mod computes the vanilla graph. Nothing makes the host do the same. The comment at `CTD/_ct_host_state_transport_owner.lua:60-66` admits the divergence.
- The parity beacon already answers "is every other human proven": `mod._ct_peer_parity:all_peers_have()`. It proves the same boon catalog, which in practice means the same build. An exact level-key identity is left to WP-CW-10.

**Steps.**
1. Part A, test first. Create `qa/lua/tests/test_ct_graph_gate_policy.lua` (register it) for a new pure module `_ct_graph_gate_policy.lua`, loaded from both trees. Cases: `mode(0, false)` returns `"modded", "solo"`; `mode(2, true)` returns `"modded", "all_peers_proven"`; `mode(1, false)` and `mode(1, nil)` return `"vanilla", "unproven_peer"`. `with_vanilla_pool(reset, reinject, fn, ...)` calls `reset`, then `fn` with the arguments, then `reinject`, and returns `fn`'s first result; when `fn` throws, `reinject` still runs and the error is rethrown.
2. Create `CTD/_ct_graph_gate_policy.lua` with `M.mode(other_humans, all_proven)` and `M.with_vanilla_pool(reset, reinject, fn, ...)` exactly as tested, plus `M.other_humans()` (`Managers.player:num_human_players() - 1`, floor 0, 0 when unavailable; `Vermintide-2-Source-Code/scripts/managers/player/player_manager.lua:489`) and `M.all_proven(mod)` (`pcall(mod._ct_peer_parity.all_peers_have, mod._ct_peer_parity)`, false when the beacon is missing).
3. In `CTD/_adventure_pool.lua`, after `reset_to_snapshot`, export `function _M.reset_pool_to_vanilla() take_snapshot(); reset_to_snapshot() end`.
4. In `CTD/_ct_adventure_runtime_owner.lua`, just above the graph owner call (`:684-691`), add `mod._ct_graph_gate_policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_graph_gate_policy")` and pass two more context keys to the graph owner: `adventure_pool = AdventurePool` and `graph_gate = mod._ct_graph_gate_policy`. The hook must call `gate.other_humans()` and `gate.all_proven(mod)` through the table each time (no local copies), so the rig can override them. In `CTD/_ct_campaign_graph_owner.lua` add the matching `assert` lines next to the existing ones (`:84-91`).
5. In the `deus_populate_graph` hook (`CTD/_ct_campaign_graph_owner.lua:284`), before any override: compute `local mode, reason = gate.mode(gate.other_humans(), gate.all_proven(mod))`; set `mod._ct_run_graph_mode = mode`; `pcall(printf, "[ct:graph] mode=%s reason=%s", mode, reason)`. When `mode == "vanilla"`: `local graph = gate.with_vanilla_pool(AdventurePool.reset_pool_to_vanilla, AdventurePool.inject_pool, func, base_graph, seed, config, dominant_god, with_belakor)`; then on the server call `broadcast_graph_snapshot(graph)`, on a client `apply_graph_snapshot(graph)`; `return graph`. Leave the existing two branches untouched for `"modded"`.
6. Part B. Repeat steps 2, 3 and 5 in the public tree: new file `CTP/_ct_graph_gate_policy.lua` (identical), export in `CTP/_adventure_pool.lua` after `:521`, gate at the top of the hook at `CTP/chaos_wastes_tweaker.lua:5622` using a `mod:dofile` of the policy stored on `mod._ct_graph_gate_policy`. Keep the public entry's non-empty line count from growing.
7. Part C, dev only. In `CTD/_ct_peer_parity_owner.lua`: in the `hot_join_sync` hook (`:790`), when `mod._ct_run_graph_mode == "modded"` record `graph_watch[peer_id] = _clock + 20`. In `owner_update`, at the deadline, if `inst:peer_has(peer_id)` is false print `[ct:graph] UNPROVEN_PEER_IN_MODDED_RUN peer=<id>` and `mod:echo` one host warning. Do not kick.
8. Bump versions and changelogs. Update the comment at `CTD/_ct_host_state_transport_owner.lua:60-66`.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the new cases; `pwsh -NoProfile -File qa/check_file_sizes.ps1` does not exit 2.
- RIG: add `qa/runtime/ct_dev/wp_cw_05_graph_gate.lua` (and the same for `ct`). Before the run is created, take `local policy = get_mod("ct_dev")._ct_graph_gate_policy`, set `policy.other_humans = function() return 1 end` and `policy.all_proven = function() return false end` (restore both at the end), `T.set` `inject_adventure_maps = true` and `replace_shrines_with_missions = true`, then start a Chaos Wastes run. Assertions: `host_expect_log = { "%[ct:graph%] mode=vanilla reason=unproven_peer" }`; for every node of `rc:_get_graph_data()` with a string `level`, `mod._ct_adventure_base_from_level_key(node.level) == nil` (`CTD/_ct_adventure_runtime_owner.lua:111`). A second case without the overrides expects `mode=modded reason=solo`. If the `deus` arena creates the run before `run(T)` executes, start from arena `keep` and create the run with the engine call in `docs/audits/2026-11-13_FORMAL_AUDIT/evidence/C1.md` section 4.3 row 30; if that is not possible the case reports INCONCLUSIVE and the offline tests stand.
- Evidence class: U closes the policy. R closes the single-peer behaviour. Host and client agreement is class C.

**Guardrails.** Do not remove or weaken the lobby hash shim. Do not gate `pre_register_adventure_lookups`: registration stays unconditional (family brief, trap 2). Do not kick anyone in this card. Do not touch the runtime curse hooks in `CTD/_ct_node_entry_owner.lua`. In dev, publish the policy on `mod._ct_graph_gate_policy` from the runtime owner, not from the entry (size ratchet).

**Stop and escalate if.** A source-pinning test forbids a new identifier in `CTD/_ct_campaign_graph_owner.lua` (its header says some identifiers must never appear in the file): report the exact assertion. The vanilla branch changes the graph in a solo run. Decision D-CW-01 is answered differently from the default.

### WP-CW-06 Stop enemy_tweaker hook wrappers running vanilla twice

| Field | Value |
|---|---|
| Priority | P1 (double execution and swallowed errors in spawn code; hides root causes) |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | none (it removes a mechanism that produced the double-fault log lines in the #470 session) |
| Source | A4-F07 |
| Streams | `enemy_tweaker/` only (single stream) |

**Goal.** Every hook registered through `_hook_wrap` or `_hook_wrap_table` calls the vanilla function at most once per invocation, whatever fails.

**Context.** ET = `enemy_tweaker/scripts/mods/enemy_tweaker/`.
- `_hook_wrap` runs the hook body under `pcall`; on error it calls `func(self, ...)` again and returns nil if that also fails (`ET/_et_protect.lua:65-82`; table form `:116-128`). Bodies call `func` first and do the mod's work after (`ET/_et_director_hooks.lua:33-56`), so an error in the mod's part runs vanilla a second time.
- The authors documented the damage on `ConflictDirector.update` and fixed only that hook with `_hook_wrap_tick` (`ET/_et_protect.lua:131-199`).
- 21 hooks still use the old wrapper, including `ConflictDirector.init` and `refresh_conflict_director_patches` (`ET/_et_director_hooks.lua:33,69`), `HordeSpawner.spawn_horde` and `spawn_unit` (`ET/_et_event_size.lua:72`, `ET/_et_swaps.lua:250`), `SpawnZoneBaker.spawn_amount_rats` (`ET/_et_roaming.lua:277`) and `BreedFreezer.try_mark_unit_for_freeze` (`ET/_et_pacing.lua:356`).
- The wrapper is exported as `ET.hook_wrap` and `ET.hook_wrap_table` (`ET/_et_protect.lua:253-255`), so it can be tested with a stub `mod`.

**Steps.**
1. Test first. Create `qa/lua/tests/test_et_hook_wrap_single_vanilla.lua` (register it). Load `ET/_et_protect.lua` the way `qa/lua/tests/test_et_pacing_tick_guard.lua` does (stub `mod` with `hook = function(_, class, method, fn) hooks[tostring(class) .. "." .. method] = fn end`, `warning`, `info`, and a `mod._et` table with `rt_register` and `dbg_alert`). Register one hook through `ET.hook_wrap("X", "m", "t", body)` per case and call the captured function with a counting `func`. Cases: (a) body throws before calling `func`: `func` ran exactly once and its results are returned; (b) body calls `func` and then throws: `func` ran exactly once and the wrapper returns `func`'s results, not nil; (c) `func` itself throws inside the body: `func` ran exactly once and the wrapper returns nil; (d) body succeeds and returns five values: all five come back. Repeat (a) to (c) for `ET.hook_wrap_table`. Cases (b), (c) and (d) fail today.
2. In `ET/_et_protect.lua` add a local helper `_tracked(func)` returning `call, state`: `call(...)` sets `state.started = true`, stores `state.n, state.results = select("#", ...)`-style packed results of `func(...)`, sets `state.finished = true`, and returns them with `unpack(state.results, 1, state.n)`.
3. Rewrite `_hook_wrap`: pass `call` to the body instead of `func`. On body success return all results (pack with `select("#", ...)`, not four fixed slots). On body error log as today, then: if `state.finished`, return the stored vanilla results; else if `state.started`, return nil (vanilla threw: never re-enter it); else run `func(self, ...)` once under `pcall` as the fallback. Apply the same logic to `_hook_wrap_table`. Do not change `_hook_resolve_first_once` or `_hook_wrap_tick`.
4. Keep the log prefixes `[et:hook]` unchanged and add the word `vanilla_runs=1` to the fallback line so a log reader can tell the new path.
5. Bump `MOD_VERSION` at `ET/enemy_tweaker.lua:3`, add a changelog entry.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the new cases and with `test_et_pacing_tick_guard` still green.
- RIG: no new case. Every existing enemy_tweaker rig case gains `host_forbid_log = { "%[et:hook%] .* vanilla fallback ALSO errored" }`; one `mission:military` boot with enemy_tweaker loaded must PASS `T.expect_rt("enemy_tweaker", "spawn_pacing_hook_targets_present")`.
- Evidence class: U closes finding A4-F07.

**Guardrails.** Do not convert swallowed vanilla errors into rethrows in this card (that changes live behaviour; record it as a follow-up). Do not touch the 21 call sites. Bodies that wrap `func` in their own `pcall` (for example `ET/_et_roaming.lua:236-245`) keep working because `call` has the same signature.

**Stop and escalate if.** A hook body is found that calls `func` more than once on purpose. `test_et_pacing_tick_guard` starts failing.

### WP-CW-07 Stop enemy_tweaker join fence kicking players on unknown census

| Field | Value |
|---|---|
| Priority | P1 (players without the mod are kicked from a mod advertised as host-only; same mechanism as the #1497 soft-lock) |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | #1497 (advances: remote-peer half of the same defect), #451, #324 |
| Source | A4-F08 |
| Streams | `enemy_tweaker/` only (single stream) |

**Goal.** A joining player is held and kicked only when a custom breed is really alive or queued, the host is told why, and an unknown census never counts as "alive".

**Context.** ET = `enemy_tweaker/scripts/mods/enemy_tweaker/`.
- The fence hooks `GameNetworkManager.set_peer_synchronizing` and `NetworkServer.is_network_state_fully_synced_for_peer` (`ET/_et_custom_breed_parity.lua:386,433`). A joiner without exact proof is held while `_custom_state_live()` is true and kicked after `HOT_JOIN_TIMEOUT = 10` s (`:127`, `:284-310`).
- Proof cannot arrive during the hold for a first-time joiner: VMF pings a peer only after `add_remote_player`, which vanilla runs after sync (`<repos>/Vermintide-Mod-Framework/vmf/scripts/mods/vmf/modules/core/network.lua:366-373`; `Vermintide-2-Source-Code/scripts/network/peer_states.lua:432,450`). So the hold always ends in a kick.
- `_custom_state_live()` (`:229-264`) returns true for unknown states: `census-unavailable` (`:235`), `queued-census-unavailable` (`:239`), `live-census-invalid` (`:249`), `queued-census-invalid` (`:256`). The last one fires whenever `num_queued_spawn_by_breed` has no entry for the breed. #1497 was this path holding the local host in the keep; the fix bypassed the local peer only (`:329-351`).
- A missing counter is safe to read as zero: vanilla seeds one counter per entry of `Breeds` (`Vermintide-2-Source-Code/scripts/managers/conflict_director/conflict_director.lua:296-299`) and does arithmetic on it when a unit is queued (`:1788`), so a nil counter means that breed was never queued in this director.
- The custom breeds are `et_chosen_greataxe` and `et_skaven_warlord` (`ET/_et_custom_breed_identity.lua:9-18`).

**Steps.**
1. Test first. In `qa/lua/tests/test_et_custom_breed_parity.lua` (it already loads the module with stubs) add cases for a remote peer id that is not the server's: (a) `Managers.state.conflict = { count_units_by_breed = function() return 0 end, num_queued_spawn_by_breed = {} }`: `ET.custom_breed_state_live()` returns `false`, the `set_peer_synchronizing` hook calls the native function at once and `ET.custom_breed_hot_join_phase(peer)` is `"admitted"`; (b) a breed name missing from the global `Breeds` is not live; (c) `count_units_by_breed` returns 1: phase is `"pending"`; advance the module clock by 10 s through `mod.update`, call the `is_network_state_fully_synced_for_peer` hook again, and the phase is `"kicked"` with exactly one host chat line echoed; (d) `num_queued_spawn_by_breed.et_skaven_warlord = "x"` still returns true. Cases (a) and (b) fail today, and (c) fails on the chat line.
2. In `_custom_state_live()`: skip a spec whose name is not in `rawget(_G, "Breeds")` (wrap the per-spec body in `if registered then ... end`; Lua 5.1 has no `goto` in the test host). Read `local queued_count = rawget(queued_by_breed, name)` and treat `nil` as 0. Leave every other fail-closed branch as it is.
3. In `_kick_once` (`:284-296`), after the existing log line, add one `mod:echo` to the host: `"[et] A player could not join: a custom boss is alive and they do not have Tweaker: Enemies. They can join after it dies."`.
4. In `ET/enemy_tweaker_localization.lua` append to `warlord_in_monster_pool_tooltip` (`:243`): `" While this boss is alive, players without this mod cannot join."`. Correct the comment block above the fence and the row at `enemy_tweaker/ENGINE_SURFACE.md:95` to say that proof cannot arrive before sync for a first-time joiner.
5. Bump `MOD_VERSION` at `ET/enemy_tweaker.lua:3`, add a changelog entry.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the new cases; `test_et_issue1497_local_host_fence` stays green.
- RIG: add `qa/runtime/enemy_tweaker/issue_1497_census_not_live.lua`. Case 1, arena `keep`: `local live, reason = get_mod("enemy_tweaker")._et.custom_breed_state_live()`; `T.expect_eq(live, false, tostring(reason))`. Case 2, arena `mission:military`: same expectation before any spawn; then `T.cmd("et_spawn_chosen")`, `T.wait_until(function() return Managers.state.conflict:count_units_by_breed("et_chosen_greataxe") > 0 end, 20, "chosen alive")`, `T.expect_eq((get_mod("enemy_tweaker")._et.custom_breed_state_live()), true, "live while alive")`. `host_forbid_log = { "%[et:451%] hot%-join sync HELD", "%[et:451%] hot%-join sync KICKED" }`.
- Evidence class: U and R close finding A4-F08 for the false-positive path. The kick of a real joiner while a boss is alive is class C and is intended behaviour under decision D-CW-04.

**Guardrails.** Do not remove the hold or the kick. Do not change the local-host bypass. Do not weaken the sender floor (`ET/_et_custom_breed_parity.lua:100-113`): it is what keeps custom breeds from spawning in a mixed lobby. Do not edit `ET/_lib_peer_parity.lua`.

**Stop and escalate if.** Case 1 of the rig file reports `live == true` after the fix: attach `reason`. Decision D-CW-04 is answered differently from the default.

### WP-CW-08 Make client settings come only from the session host

| Field | Value |
|---|---|
| Priority | P1 (a client's own settings act in other people's games; stale host values survive into later sessions) |
| Size | M |
| Agent | any |
| Depends on | none |
| Issues | none open |
| Source | A4-F06, A4-F16 |
| Streams | both (identical logic; public keeps it in the monolith entry) |

**Goal.** On a client every host-scope Chaos Wastes setting resolves to the value sent by the current session host, or to the widget default when that host has sent nothing; settings chunks from any other sender are dropped.

**Context.** CTD = `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/`, CTP = `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/`.
- `effective_setting(name)` returns `mod:get(name)` on the host, the synced value on a client, and the client's own saved value when nothing was synced (`CTD/chaos_wastes_tweaker_dev.lua:1142-1152`; public `CTP/chaos_wastes_tweaker.lua:2157-2167`).
- The cache is never cleared: `_ct_host_settings` and `_ct_host_sync_received` are written at `CTD/_ct_host_state_transport_owner.lua:328-331` and nowhere reset (declared `:121-122`; public `:1301-1302`, `:1500-1502`). Values from an earlier host stay in force in later lobbies.
- The receiver accepts a payload from any peer (`CTD/_ct_host_state_transport_owner.lua:277-362`; public `:1448`).
- The host sends settings only at run setup and after edits (`CTD/_ct_run_creation_owner.lua:381`, `CTD/_ct_host_state_transport_owner.lua:250`), so a late joiner never receives them.
- Why it matters: vanilla trusts client-side amounts. Example: the coin hook multiplies a pickup on the client (`CTD/chaos_wastes_tweaker_dev.lua:1005-1037`) and the host credits whatever the client sends (`Vermintide-2-Source-Code/scripts/managers/game_mode/mechanisms/deus_run_controller.lua:900-909,929-933`).
- The session host's peer id is `Managers.mechanism:server_peer_id()` (`Vermintide-2-Source-Code/scripts/managers/game_mode/game_mechanism_manager.lua:378,413-415`). Per-peer settings are listed in `PER_PEER_SETTING_NAMES` (`CTD/_ct_host_state_transport_owner.lua:44-76`).

**Steps.**
1. Test first. Create `qa/lua/tests/test_ct_host_settings_policy.lua` (register it) for a new pure module `_ct_host_settings_policy.lua`, loaded from both trees. `resolve(is_server, scope, local_value, host_known, host_value, default_value)`: host returns `local_value`; `scope == "local"` returns `local_value`; client with `host_known` returns `host_value`, including `false`, and `default_value` when `host_value` is nil; client without `host_known` returns `default_value`. `accept(is_server, sender_peer_id, server_peer_id)`: false on the host, false when either id is nil, false when they differ, true when equal.
2. Create `CTD/_ct_host_settings_policy.lua` and an identical `CTP/_ct_host_settings_policy.lua` with those two functions.
3. Dev transport (`CTD/_ct_host_state_transport_owner.lua`): in `_collect_setting_ids` (`:78-102`) also fill a `DEFAULTS[setting_id] = node.default_value` map. In the `ct_sync_host_settings_chunk` receiver, after the schema check, drop the chunk unless `Policy.accept(is_server, sender_peer_id, Managers.mechanism:server_peer_id())`; print one `[ct_sync] dropped chunk from non-host peer=<id>` line. On a completed payload store `_ct_host_peer_id = sender_peer_id`. Add `host_known()`: `_ct_host_sync_received and _ct_host_peer_id == Managers.mechanism:server_peer_id()`; when it is false and the cache is not empty, clear `_ct_host_settings` and `_ct_host_sync_received`. Export `resolve = function(name) ... Policy.resolve(...) end` in the returned table (`:765-776`) and make the existing `host_sync_received` export call `host_known()`. Apply the same sender test to the `ct_graph_snapshot_chunk` receiver (`:681`).
4. Dev entry: replace the body of `effective_setting` (`CTD/chaos_wastes_tweaker_dev.lua:1142-1152`) with `return _ct_host_transport.resolve(name)`. The entry must not gain lines (size ratchet). Change the third value of `mod._ct_effective_setting_source` (`:1158-1162`) from `"local_fallback"` to `"vanilla_default"`.
5. Late joiners: in `CTD/_ct_peer_parity_owner.lua` `gated_feature_spec.on_enable` (`:751-755`) add `if mod._ct_broadcast_host_settings then pcall(mod._ct_broadcast_host_settings, "parity_enabled") end`. The function already returns on a client (`CTD/_ct_host_state_transport_owner.lua:375-377`).
6. Public: make the same changes in `CTP/chaos_wastes_tweaker.lua` (receiver `:1448-1505`, graph receiver `:1848`, resolver `:2157-2167`, widget walk that builds the synced list). Keep `mod._ct_raw_effective_setting` and the `mod._ct_official_runtime.setting` wrapper (`:2169-2185`) as they are. Keep the entry's non-empty line count from growing.
7. Bump versions and changelogs. Update the tooltip or description that tells users settings are host-decided only if one exists; do not add new menu text.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the new cases and with `test_ct_dev_shop_false_authority` and `test_ct_starting_coins` still green. `pwsh -NoProfile -File qa/check_file_sizes.ps1` does not exit 2.
- RIG: add `qa/runtime/ct_dev/wp_cw_08_host_path.lua` (and a copy for `ct` without the first assertion: public has no `_ct_effective_setting_source`), arena `keep`: `local m = get_mod("ct_dev")`; `T.expect_eq(m._ct_effective_setting_source(), "local_host", "host reads own settings")`; for `coin_multiplier`, `shrine_boon_count`, `starting_coins`: `T.expect_eq(m._ct_effective_setting(id), m:get(id), id)`. `host_forbid_log = { "%[ct_sync%] dropped chunk" }`.
- Evidence class: U closes findings A4-F06 and A4-F16 at policy level; R closes "host behaviour unchanged". The client path is class C.

**Guardrails.** Do not change which settings are per-peer. Do not change the chunk format or `CT_RPC_SCHEMA`. A host value of `false` must win over a client's saved `true` (existing test). Do not add lines to the dev entry.

**Stop and escalate if.** `Managers.mechanism:server_peer_id()` is nil on a client inside a lobby (then use the id the receiver sees as the first sender in this session and report it). Decision D-CW-05 is answered differently from the default.

### WP-CW-09 Replace constant-comparison regression checks and return check results as data

| Field | Value |
|---|---|
| Priority | P1 (verification evidence: these checks pass whether or not the fix works) |
| Size | L. Split: step 1-4 harness (M); step 5 per mod (ct_dev, ct, event_tweaker, enemy_tweaker) |
| Agent | any |
| Depends on | none |
| Issues | none closed. Affects every issue whose card cites a `/ct_regression_test` result |
| Source | A4-F09 |
| Streams | all four trees |

**Goal.** Each mod exposes `mod.rt_run()` returning one row per check with status PASS, FAIL or SKIP, and no check compares a constant from the mod's own source with a literal.

**Context.** CTD = `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/`, CTP = `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/`, EVT = `event_tweaker/scripts/mods/event_tweaker/`, ET = `enemy_tweaker/scripts/mods/enemy_tweaker/`.
- Example of the pattern: `CTD/_ct_regression.lua:609-617` passes when `CT_ALTAR_REUSE_HOOK_MARKER` equals a literal, and that global is assigned the same literal at `CTD/chaos_wastes_tweaker_dev.lua:702`. Nothing about the hook is read.
- `git grep -cE 'MARKER ~= "'` finds 37 such comparisons in dev scripts, 18 in public, 1 in event_tweaker, 0 in enemy_tweaker.
- Three harness variants exist. ct prints PASS, FAIL and SKIP (a check returns a string starting with `skip:`; `CTD/chaos_wastes_tweaker_dev.lua:335-367`). event_tweaker has no SKIP (`EVT/_evt_regression.lua:24-39`). enemy_tweaker skips through a `precondition` option (`ET/_et_regression.lua:24-64`). All print free text to chat and log.
- The rig records every check of these suites as an assertion, so a constant check produces a false PASS in every run.

**Steps.**
1. Test first. Create `qa/lua/tests/test_rt_harness_rows.lua` (register it). Load `EVT/_evt_regression.lua` and `ET/_et_regression.lua` with a stub `mod` (`command`, `echo`, `info`, `warning`, and `mod._evt` / `mod._et` tables). Register three checks through each harness: one returning nil, one returning `"boom"`, one skipping (`"skip: no run"` for event_tweaker, a false `precondition` for enemy_tweaker). Assert `mod.rt_run()` returns three rows `{ name = ..., status = ..., detail = ... }` with statuses `PASS`, `FAIL`, `SKIP` in registration order, and that a check that throws is `FAIL` with the error text as detail.
2. `EVT/_evt_regression.lua`: move the loop into `function mod.rt_run()` that returns the rows; treat a returned string starting with `skip:` as SKIP. The chat command prints from the rows, keeping the existing PASS and FAIL line formats and adding a SKIP line and a skipped count.
3. `ET/_et_regression.lua`: same `mod.rt_run()`, keeping the `precondition` mechanism and the existing line formats.
4. ct: create `CTD/_ct_regression_harness.lua` returning `{ register = fn, run = fn }` with the logic now at `CTD/chaos_wastes_tweaker_dev.lua:335-367`; in the entry replace that block with `local _rt_harness = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_regression_harness")`, `local _rt_register = _rt_harness.register`, `mod._ct_rt_register = _rt_register`, `mod.rt_run = _rt_harness.run` (the entry must end up shorter). In `CTP/chaos_wastes_tweaker.lua` refactor the same loop in place into `mod.rt_run` without growing the file.
5. Constant checks. List them with `git grep -nE 'MARKER ~= "' -- <tree>/scripts`. Known dev names: `spawn_pickup_returns_both_values`, `issue299_chest_revive_team_teleport_ordered`, `dormant_setting_keys_not_consumed`, `game_round_ended_swallows_error`, `no_roamers_strip_arity_356`, `perf104_census_installed`, `starting_coins_setter_not_adder`, `altar_reuse_hook_on_open_chest`, `open_chest_hook_singleton`, `cot_enemy_multiplier_cursed_chest_only`, `cot471_spawn_composition_probe`, `cot471_placement_topup`, `altar_visual_probe_present`, `upgrade_altar_rarity_decouple`, `morgrim143_probe_installed`, `morgrim143_renorm_fix`, `manann_tempest_trait_cooldown_note`, `citadel145_probe_installed`, `citadel145_force_finale_god_fix`, `bot_weap_opened_rarity_pre_bump`, `endless_bombs_strip_on_expiry`, `variadic_hooks_arity_preserved`, `home_brewer_add_buff_multireturn_preserved`, `chunk_sends_paced_not_bursted`; public has 14 of the same names; event_tweaker `issue532_mutator_preview_wired`. For each one read the body, then either (a) rewrite it to read state the fix changes (a `BuffTemplates` or `DeusPowerUpTemplates` field, a setting-driven function's output for a fixed input, a live run-state value) or (b) delete it. Do not replace a marker with another constant or with "function exists". When a check is deleted, delete the now unused `*_MARKER` global and its context entry too.
6. Before deleting a name run `git grep -n "<name>"` and update every hit: `REGRESSION_CHECKLIST.md` rows, offline tests that execute the check body, rig plans. List deleted names in each mod's `CHANGELOG.md` entry. Bump the four versions.

**Acceptance (machine, no human).**
- OFFLINE: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0 with the new cases. `git grep -nE 'MARKER ~= "' -- chaos_wastes_tweaker_dev/scripts chaos_wastes_tweaker/scripts event_tweaker/scripts enemy_tweaker/scripts` prints nothing. `pwsh -NoProfile -File qa/check_file_sizes.ps1` does not exit 2.
- RIG: add `qa/runtime/<mod>/wp_cw_09_rt_rows.lua` for each of the four mod ids, arena `keep`: `local rows = get_mod(id).rt_run()`; `T.expect(#rows > 0, "rows returned")`; for every row `T.expect(row.status == "PASS" or row.status == "SKIP", row.name .. ": " .. tostring(row.detail))`.
- Evidence class: U and S close finding A4-F09. A FAIL row in the rig case is a product finding for the owning mod, not a failure of this card.

**Guardrails.** Keep the existing chat and log line text for PASS and FAIL: other tooling may parse it. If a harness WP in track H defines another entry-point name, keep `rt_run` as an alias. Do not weaken a check that reads engine state. Do not add lines to the dev entry.

**Stop and escalate if.** A constant check is the only evidence named in an open issue's newest test card: list the issue number and the check name instead of deleting. More than five rewritten checks FAIL in the first rig run (report them; do not edit them to pass).

### WP-CW-10 Reconcile the two Chaos Wastes trees into one source tree

| Field | Value |
|---|---|
| Priority | P1 (every fix must be written twice; a naive promotion would delete the public wire fence) |
| Size | L. Seven stages, one merged change per stage; stage 4 is one change per module |
| Agent | strong: each stage needs a judgment on which implementation wins and a port of a 22-hook fence without changing wire behaviour |
| Depends on | WP-CW-02, WP-CW-03, WP-CW-04 part A, WP-CW-08 (so both trees carry those fixes before the merge) |
| Issues | #426, #1191 (advances), and every public-release issue of this family indirectly |
| Source | A4-F05, A4-F10, A4-F14 |
| Streams | both, converging on the dev layout |

**Goal.** `chaos_wastes_tweaker/` equals `chaos_wastes_tweaker_dev/` after mod-id normalisation, except for one stream descriptor file, with no public behaviour lost.

**Context.** CTD = `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/`, CTP = `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/`.
- Both are `0.7.354`. Public entry 13,294 lines, dev entry 1,597. 12 files exist only in CTP, 57 only in CTD, 37 in both; 21 of those are identical after replacing `chaos_wastes_tweaker_dev` and `ct_dev`, 16 differ.
- Public is ahead on wire safety: 22 hooks registered through `register_hook` (`CTP/_ct_peer_parity_owner.lua:739-1115`) and a 29-row catalog (`ct-public-wire-v1`). Dev registers 2 parity hooks (`CTD/_ct_peer_parity_owner.lua:790,827`) and a 33-row catalog (`CTD/_ct_wire_policy.lua:32-83`): the 4 extra rows are `ct_boon_anath_raema_swiftness`, `ct_kill_heal` and their two `power_up_*` buffs.
- Dev is ahead on structure and guards: owner modules, `NetworkedFlowStateManager.flow_cb_create_state` cap guard (`CTD/_ct_adventure_runtime_owner.lua:487`), lobby-browser filter (`:19`), replacement compensation, mission group masters.
- Both trees define the same globals (`_ct_chunk_send_queue`, `_ct_enqueue_chunk`; `CTD/_ct_host_state_transport_owner.lua:180,206`, `CTP/chaos_wastes_tweaker.lua:1360,1386`) and the same chat commands. Nothing stops both loading together.
- Measuring command (Git Bash, repo root). Today it prints 16 names: `N='s/chaos_wastes_tweaker_dev/chaos_wastes_tweaker/g; s/ct_dev/ct/g'; for f in chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/*.lua; do b=$(basename "$f" | sed 's/^chaos_wastes_tweaker\(_data\|_localization\)\?\.lua$/chaos_wastes_tweaker_dev\1.lua/'); d=chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/$b; [ -f "$d" ] && ! diff -q <(sed "$N" "$d") <(sed "$N" "$f") >/dev/null && echo "$b"; done` (both sides are normalised because some file names contain `ct_dev`)

Inventory (which side wins). Stage 0 copies this table into `chaos_wastes_tweaker_dev/DEVELOPMENT.md` and corrects it against the real diff before any merge.

| Module group | Winner | Action |
|---|---|---|
| Entry (`chaos_wastes_tweaker*.lua`) | dev layout | Public monolith is replaced last (stage 6), after every public-only behaviour has a home in a dev module |
| `_ct_peer_parity_owner.lua`, `_ct_wire_policy.lua`, `_ct_wire_runtime.lua`, `_ct_wire_bootstrap.lua` | public | Port into dev (stage 2). Catalog rows become stream data: 29 shared rows plus 4 dev-only rows |
| `_lib_network_lookup.lua` | public (shared library) | Add dev as a consumer in `tools/shared_lib/manifest.psd1` and sync (stage 1) |
| `_ct_official_verify_runtime.lua`, `_ct_diag_official_apply_evidence.lua`, the eight `/verify_ct_*` commands | public | Port as they are (stage 3) |
| `_ct_official_boon_repairs.lua`, `_ct_official_chest_cap.lua`, `_ct_official_chest_rescue.lua`, `_ct_official_collectibles.lua`, `_ct_official_cooldowns.lua`, `_ct_official_shop.lua`, `_ct_official_feature_leaf.lua` | decide per module | Stage 4: if a dev owner already gives the same behaviour, run the public case file against dev and drop the public module; otherwise port it |
| `_adventure_pool.lua`, data, localization, `_ct_blessed_bots.lua` | dev | Check the two public-only missions first (decision D-CW-07) |
| Nine shared files that differ by under 25 lines (`_ct_start_shrine_runtime.lua`, `_ct_miasma.lua`, `_ct_dev_mission.lua`, `_ct_boon_pricing_runtime.lua`, `_ct_progressive_elite_runtime.lua`, `_ct_progressive_modifier_runtime.lua`, `_ct_bomb_cooldown_display.lua`, `_ct_chest_revive_policy.lua`, `_ct_chest_count_audit_core.lua`) | read each diff | Take the line that has a test; if neither has, keep dev and add the test |
| 57 dev-only modules | dev | Each gets a stream flag: diagnostics, audits and the two dev-only boons are off in the public stream |

**Steps.**
1. Stage 0, safety. At the top of both entries add a sibling guard: if `get_mod("<other id>")` exists and has `_ct_stream_loaded`, `mod:echo` one error and `return`; otherwise set `mod._ct_stream_loaded = true`. Remove the same number of comment-only lines so neither entry grows. Add an offline test that runs the guard prologue with a stub sibling. Write the corrected inventory table into `chaos_wastes_tweaker_dev/DEVELOPMENT.md`.
2. Stage 1, lookup registration. Add `chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_lib_network_lookup.lua` to the consumer list at `tools/shared_lib/manifest.psd1:126-132` and run `tools/shared_lib/sync-shared-libs.ps1`. Route the three hand-written appenders through it: `CTD/_ct_boon_registry.lua:124-133`, `CTD/_ct_wire_policy.lua:217-234`, `CTD/_adventure_pool.lua:542-555`. Test first: a case in `qa/lua/tests/test_ct_426_exact_catalog.lua` that a sparse or asymmetric lookup is rejected instead of extended.
3. Stage 2, wire fence. Make `ct_public_426_shop_receiver_cases.lua`, `ct_public_426_sync_admission_cases.lua`, `ct_public_426_terminal_admission_cases.lua`, `test_ct_public_426_owner.lua` and `test_ct_public_426_wire_contract.lua` take the tree root as a parameter and run against both trees: they fail on dev first. Then port `_ct_wire_runtime.lua`, `_ct_wire_bootstrap.lua`, the public `_ct_wire_policy.lua` (plus the 4 dev rows behind a stream flag) and the `register_hook` block into the dev module layout. Remove a dev grant-time gate only when the ported test that covers it passes. Carry WP-CW-04 part B into the ported fence.
4. Stage 3, verification commands. Port `_ct_official_verify_runtime.lua` and `_ct_diag_official_apply_evidence.lua` and the eight commands `verify_ct_altar_reroll`, `verify_ct_ammo_bounds`, `verify_ct_anath_raema`, `verify_ct_chest_cap`, `verify_ct_citadel`, `verify_ct_linked_pickups`, `verify_ct_progression`, `verify_ct_trial_placement`.
5. Stage 4, official modules. One module per change, using `ct_official_boon_repair_cases.lua`, `ct_official_cooldown_cases.lua`, `ct_official_feature_cases.lua`, `ct_official_rescue_cases.lua`, `ct_official_shop_cases.lua` as the contract. Run each case file against dev before deciding.
6. Stage 5, data. Reconcile settings: 30 widget ids (containers included) exist only in dev, 13 only in public (`dlc_group_*` containers, `cw_scenarios_group`, `event_missions_group`, `enable_adventure_crater`, `enable_adventure_dlc_reikwald_river`). Container ids hold no value, so no migration is needed for them.
7. Stage 6, stream descriptor. Add `_ct_stream.lua` returning `{ id, public, disabled_modules, extra_catalog_rows }`; the manifest skips disabled modules. Replace the public tree's scripts with the normalised dev scripts plus its own `_ct_stream.lua`. Generating the public tree mechanically is a release-pipeline concern (track P); this card ends when the trees are equal.

**Acceptance (machine, no human).**
- OFFLINE, every stage: `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0; `pwsh -NoProfile -File qa/check_file_sizes.ps1` does not exit 2. After stage 2: the five public #426 suites pass against both trees. After stage 6: the measuring command prints only `_ct_stream.lua`, and `ls chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker | wc -l` equals the dev count.
- RIG, every stage: one `keep` boot per stream (never both in one boot) with `wp_cw_09_rt_rows.lua` or, before WP-CW-09, `T.cmd("ct_regression_test")` and `host_forbid_log = { "FAIL:" }`. The set of check names per stream after a stage must contain the set before it, except names the stage's changelog lists as removed. After stage 3 the public boot also runs each `/verify_ct_*` command and expects no `FAIL`.
- Evidence class: S and U close findings A4-F05, A4-F10 and A4-F14. Co-op wire behaviour stays class C.

**Guardrails.** Never copy a whole file across trees before its stage. Never delete a public behaviour without a test or rig case that passes on the dev implementation. Keep the two beacon channel names and catalog identities distinct per stream. Do not grow either entry. Do not publish from a half-merged tree: each stage must leave both streams bootable.

**Stop and escalate if.** A public test cannot be made to pass against dev inside its stage. A stage would change a catalog identity string for the public stream. Decisions D-CW-02, D-CW-06 or D-CW-07 are answered differently from the defaults.

### WP-CW-11 Remove the global `table.clone` hook from enemy_tweaker

| Field | Value |
|---|---|
| Priority | P2 (process-wide change to a core utility; hides an engine assert for every mod and for rig runs) |
| Size | S |
| Agent | any |
| Depends on | none |
| Issues | none |
| Source | A4-F13 |
| Streams | `enemy_tweaker/` only |

**Goal.** enemy_tweaker no longer hooks `table.clone`, and a 15x roaming multiplier still loads a mission.

**Context.** ET = `enemy_tweaker/scripts/mods/enemy_tweaker/`.
- `ET/_et_roaming.lua:271-275` hooks `table.clone` and forces `skip_metatable = true` on every clone in the process. The comment (`:249-270`) says this cuts memory per clone.
- Vanilla `table.clone` never copies metatables. The flag only disables `assert(mt == nil or mt.__mt_cloneable, "Metatables will be sliced off")`, and the function recurses through the global name, so every nested table pays the hook dispatch (`Vermintide-2-Source-Code/foundation/scripts/util/table.lua:31-49`).
- Effect today: no memory gain, slower deep clones, and an engine assert switched off for all mods whenever enemy_tweaker is loaded. A rig run with and without enemy_tweaker can therefore differ for unrelated mods.

**Steps.**
1. Baseline before the change. Add `qa/runtime/enemy_tweaker/wp_cw_11_roaming_15x.lua`, arena `mission:military`, plan option `roaming_size_multiplier = 15`. In `run(T)`: `T.local_hero()` (level reached), `T.note("lua_kb", collectgarbage("count"))`. `host_forbid_log = { "Metatables will be sliced off", "%[et:hook%] .* errored" }`. Run it and keep the summary.
2. Delete the hook block at `ET/_et_roaming.lua:271-275`. Rewrite the comment at `:249-270` and the comments at `:359-373` to state the engine fact above. Leave `_AMBIENT_EFFECTIVE_MULT_CAP = 15`.
3. Update the row at `enemy_tweaker/ENGINE_SURFACE.md:83` and the mention at `:22`. Bump `MOD_VERSION`, add a changelog entry.
4. Run the rig case again.

**Acceptance (machine, no human).**
- OFFLINE: `git grep -n 'mod:hook(table' -- enemy_tweaker` prints nothing. `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0.
- RIG: `wp_cw_11_roaming_15x.lua` PASS after the change, with `lua_kb` within 10 percent of the baseline note.
- Evidence class: S and R close finding A4-F13.

**Guardrails.** Do not re-add a global hook under another name. Do not lower the 15x cap to make the case pass.

**Stop and escalate if.** The log shows `Metatables will be sliced off` after the change: attach the traceback. That means one specific clone needs the flag; the fix is to pass `true` at that call site inside enemy_tweaker's own hook, not to hook `table.clone`.

### WP-CW-12 Apply the common module standard to event_tweaker and enemy_tweaker

| Field | Value |
|---|---|
| Priority | P2 (removes the structural causes behind WP-CW-01, 06, 07 and 11; gives WP-CW-10 its target shape) |
| Size | L. Split by rule: R6 and R7 first (S each), then R9 and R13 (M each) |
| Agent | any for R6, R7, R13; strong for R9 (touches every hook) |
| Depends on | WP-CW-01, WP-CW-06, WP-CW-09, WP-CW-11 (they satisfy R8, R11, R12 and R14) |
| Issues | none |
| Source | A4 section 8 |
| Streams | `event_tweaker/`, `enemy_tweaker/`. `chaos_wastes_tweaker_dev/` is measured only; it reaches the standard through WP-CW-10 |

**Goal.** event_tweaker and enemy_tweaker pass every check in the table below, and the measured status of the three mods is recorded.

**Context.** event_tweaker is the repo's module-split template and enemy_tweaker follows it, but the rules are conventions: the template's own safety hook broke the base-class rule (WP-CW-01). The checklist turns each rule into a command. `<tree>` is the mod folder; `<M>` is `<tree>/scripts/mods/<tree>`. "Today" was measured on 2026-11-13 at commit `592253d1`.

| # | Rule | Check (pass condition) | Today: event_tweaker / enemy_tweaker / ct_dev |
|---|---|---|---|
| R1 | The entry is a manifest: version, banner, ordered `mod:dofile` list | `git grep -c "mod:hook" -- <M>/<tree>.lua` prints nothing; entry under 150 lines | pass (70 lines) / pass (103) / fail (1,597 lines, 4 hooks) |
| R2 | Data shared by data, localization and script lives in `require`d modules | `git grep -n "mod\._" -- <M>/<tree>_data.lua <M>/<tree>_localization.lua` shows no read of a field the script sets | pass (3 hits, comments) / pass (5 hits, fields the data file sets itself from `enemy_tweaker_breeds.lua`) / pass (0 hits) |
| R3 | One funnel per effect, guards in front of it as separate modules | The funnel function is named in `DEVELOPMENT.md` and every caller of the effect goes through it (review) | pass (`gather_mutators`) / not measured / fail |
| R4 | Decisions live in engine-free `*_policy.lua` / `*_core.lua` modules, each loaded by an offline test | `git grep -nE "Managers\.|ScriptUnit|mod:hook" -- "<M>/*_policy.lua" "<M>/*_core.lua"` prints nothing outside comments | pass (3 files) / pass (6 files) / pass (19 files, 1 comment hit) |
| R5 | No implicit globals | `tools/luacheck/luacheck.exe <tree>/scripts --no-config --std lua51 --only 111 --formatter plain` reports 0 warnings | pass / pass / fail (51 sites, 44 names) |
| R6 | One lifecycle module assigns `mod.update` and the `mod.on_*` callbacks; other modules subscribe | `git grep -lE "^\s*mod\.(update|on_[a-z_]+) *=" -- <M>` lists one file besides `_lib_peer_parity.lua` | fail (3 files) / fail (2 files) / fail (7 files) |
| R7 | Every widget declares `scope`: `host`, `all_peers` or `local` | Offline test loads `<tree>_data.lua` with a stub `mod` and finds no leaf widget without `scope` | fail / fail / fail |
| R8 | Checks return rows through `mod.rt_run()`, support SKIP, compare no source constants | WP-CW-09 acceptance | fail / fail / fail |
| R9 | Every hook goes through one wrapper that records class, method, owner module and kind | `git grep -nE "mod:hook(_safe)?\(" -- <M>` lists only the wrapper file | fail (26 sites) / fail (15 direct) / fail (137) |
| R10 | No hook on a class that has subclasses, unless each subclass is hooked | For each recorded class `C`: `grep -rn "class([A-Za-z]*, C)" <repos>/Vermintide-2-Source-Code/scripts` is empty, or the line carries `-- base-hook-ok: <reason>` | fail until WP-CW-01 / 1 site to annotate (`GenericHealthExtension.init`) / not measured |
| R11 | No hook on `_G`, `table`, `string` or `math` except `Localize` | `git grep -nE "mod:hook(_safe)?\((_G|table|string|math)," -- <M>` shows only `Localize` | pass / fail until WP-CW-11 / pass (2 `_G` hooks: `Localize`, `deus_populate_graph`; annotate the second) |
| R12 | A protective wrapper calls vanilla at most once | WP-CW-06 offline test | n/a / fail until WP-CW-06 / not measured |
| R13 | Vanilla tables changed around a call are restored on error | Each mutate, call, restore sequence uses one helper that restores in both paths (`_call_with_override` in `enemy_tweaker/scripts/mods/enemy_tweaker/_et_protect.lua:208-222` is the model) | not measured / pass for pacing / fail (2 sites) |
| R14 | A feature that needs every player to have the mod is gated by the beacon, starts off, and never depends on proof arriving before `hot_join_sync` | The feature has an offline test for "peer without proof" and no hold-for-proof timer | fail until WP-CW-01 / fail until WP-CW-07 / fail until WP-CW-04 |
| R15 | `NetworkLookup` and breed-class tables are written only through `_lib_network_lookup.lua` and a registrar that can roll back | `git grep -nE "#lookup \+ 1|rawset\(lookup|t\[idx\] = name" -- <M>` prints nothing outside `_lib_network_lookup.lua` | pass (0 hits) / pass (0 hits) / fail (7 hits in 3 appenders) |
| R16 | Diagnostics modules install their hooks only behind one switch and are deleted when the issue closes | `git grep -c "mod:hook" -- "<M>/*diag*.lua"`: every listed file tests the switch before hooking | fail (`_evt_diagnostics.lua`, 3 hooks) / pass (no hooks in diagnostics files) / fail (3 files, 10 hooks) |

**Steps.**
1. Run every check for the three mods and write the results as a table in a "Module standard" section of each mod's existing `DEVELOPMENT.md`. Correct any "Today" value that differs.
2. R6, event_tweaker. Create `event_tweaker/scripts/mods/event_tweaker/_evt_lifecycle.lua`, loaded last in the manifest. It owns `mod.on_setting_changed` and `mod.on_disabled` and calls subscriber lists `ET.on_setting_changed_subscribers` and `ET.on_disabled_subscribers` in order. Move the bodies from `_evt_apply.lua:102-111` and `_evt_shadow_adventure.lua:451` into functions that subscribe. The `mod.update` wrapper in `_evt_guard430_curse_parity.lua:318-328` becomes an `ET.on_update_subscribers` entry driven by one `mod.update` in the lifecycle module that calls the previous `mod.update` first (the beacon library installs its own wrapper and stays as it is). Test first: an offline test that loads the lifecycle module with a stub `mod`, subscribes two functions and asserts call order and that an error in one subscriber does not stop the next.
3. R6, enemy_tweaker. The clock wrapper at `enemy_tweaker/scripts/mods/enemy_tweaker/_et_custom_breed_parity.lua:132-138` becomes a subscriber of a list drained by `_et_lifecycle.lua:125-136`. Create the list on `mod._et` in `_et_protect.lua` so it exists before the parity module loads.
4. R7. Add `scope` to every leaf widget in both data files: `host` by default; `all_peers` for the Cursed Adventure group and `mut_shadow` in event_tweaker and for `warlord_in_monster_pool` and `warlord_monster_chance` in enemy_tweaker; `local` for `personal_difficulty`. Add the offline test named in R7 for both mods.
5. R9 and R10. Add `ET.hook(class_name, method, kind, fn)` in each mod's protect or log module: it calls `mod:hook` or `mod:hook_safe` and appends `{ class, method, kind, owner }` to `ET.hook_registry`. Convert the direct sites. Add an in-game check that every recorded class exists as a global table. Annotate `GenericHealthExtension.init` with `-- base-hook-ok: subclasses that define init call super.init` after confirming it in `Vermintide-2-Source-Code/scripts/unit_extensions/generic/rat_ogre_health_extension.lua:5-6`.
6. R13, R16. Report only; do not refactor in this card.
7. Bump both versions, add changelog entries.

**Acceptance (machine, no human).**
- OFFLINE: for `event_tweaker` and `enemy_tweaker`, the checks R1, R5, R6, R7, R9, R11 pass as written in the table; `pwsh -NoProfile -File qa/check_lua_unit_tests.ps1` exits 0.
- RIG: one `keep` boot and one `mission:military` boot per mod with the regression suite (`wp_cw_09_rt_rows.lua`) all PASS or SKIP, and `host_forbid_log = { "attempt to call", "attempt to index" }`.
- Evidence class: S and U. No issue closes on this card.

**Guardrails.** Do not rename files (tests and packages pin names). Do not turn the checklist into a QA gate in this card: wiring commands into QA belongs to track T. Do not apply R6 or R9 to `chaos_wastes_tweaker_dev/` here. Keep hook registration order unchanged when converting to the wrapper (VMF drops a second hook on the same pair, and check output order follows load order).

**Stop and escalate if.** Converting a hook to the wrapper changes which hook VMF keeps for a (Class, method) pair. A widget's scope is not obvious from its tooltip: list it instead of guessing.

## Owner decisions

The owner is unavailable. Agents proceed on the default and write the decision id into the change description.

| Id | Question | Conservative default to assume |
|---|---|---|
| D-CW-01 | May a player without Tweaker: Chaos Wastes share a lobby with a host who has it? | Yes. Keep the lobby hash shim. In such a lobby the mod's map features go inert (vanilla graph and pool). Nobody is kicked. (WP-CW-05) |
| D-CW-02 | Which Chaos Wastes tree is the source of truth? | The dev module layout. Public behaviour (wire fence, official modules, verify commands) is ported into it; nothing public is dropped without a passing test. (WP-CW-10) |
| D-CW-03 | What happens to custom boons when an unproven player joins? | Strip for safety, restore automatically when every player is proven. No refund, no kick, no hold. (WP-CW-04) |
| D-CW-04 | enemy_tweaker custom boss alive when a player without the mod joins | Keep the 10 s hold and the kick, tell the host why, and treat an unknown census as "not alive". No boss despawn or swap. (WP-CW-07) |
| D-CW-05 | Should Chaos Wastes settings act on a client whose host lacks the mod? | No. Host-scope settings resolve to widget defaults until the current host sends values. (WP-CW-08) |
| D-CW-06 | Should the public stream gain the two dev-only boons (`ct_boon_anath_raema_swiftness`, `ct_kill_heal`)? | No. Public keeps its 29-row catalog; the 4 extra rows stay dev-only stream data. (WP-CW-10) |
| D-CW-07 | Public lists two missions dev dropped (`enable_adventure_crater`, `enable_adventure_dlc_reikwald_river`) | Keep them in the public stream as they are, off in dev, until a rig mission-load case decides each. (WP-CW-10) |
| D-CW-08 | Standing per-issue diagnostics in public builds | Leave as they are. Checklist rule R16 is reported, not enforced. (WP-CW-12) |
