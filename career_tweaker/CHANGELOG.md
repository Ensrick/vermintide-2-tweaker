# Career Tweaker Changelog

## 0.4.27-beta (2026-08-25) - reject malformed NetworkLookup state (#428) [not-started]

- Synchronized the canonical NetworkLookup registrar that validates the full
  dense bidirectional table with raw access before idempotence or append.
- Invalid and sparse lookup state now fails without mutation while preserving
  the exact ordered output of all 36 existing balance and Tourney buff rows.

## 0.4.26-beta (2026-08-23) - retire dormant Bardin probe (#499, #440)

- Removed the dormant, unloaded five-hook Bardin/disabler comparison probe and
  its dead per-frame tick branch from the public beta package.
- Preserved the empirical source contract as engine-free QA: all heroes still
  clone the shared movement table, Packmaster and Lifeleech consume the common
  dodge state, and Gutter Runner remains the distinct spatial/neck-node seam.
- Strengthened the public-beta gate to reject the retired file itself, while
  retaining the stable runtime check name `public_beta_issue_probes_disabled`.
  No gameplay value, hook, setting, RPC, or player-visible behavior changed.

## 0.4.25-beta (2026-08-23) - canonical NetworkLookup registration (#428) [not-started]

- Replaced Career Tweaker's two duplicate `NetworkLookup.buff_templates`
  append loops with one manifested, byte-identical copy of the repository's
  canonical bidirectional registration helper. The helper loads once before
  both the balance and Tourney owners.
- Preserved all 34 balance names followed by the two Tourney names in their
  existing order, along with unconditional stub creation, the permanent
  registered-name catalog, and every feature/parity decision.
- Malformed, asymmetric, missing, or non-numeric lookup state now rejects the
  pair rather than guessing an index. The existing exact wire-catalog identity
  consequently remains unavailable and keeps network-visible reworks at
  vanilla, preserving the fail-safe boundary.
- Added a reference-algorithm comparison across all 36 live names, every
  reachable helper rejection, exact-copy/manifest/load-order assertions, and
  an adversarial proof that a rejected row reaches the exact-catalog floor.
  No hook, RPC, setting, buff name, or network ordering changed.

This is one autonomous shared-library migration slice. It does not complete
the repository-wide #428 umbrella and does not create an in-game test card.

## 0.4.24-beta (2026-08-23) - Focused Spirit single-writer lifecycle (#472) [verify-fix]

- Repaired Focused Spirit's `buffer="both"` topology. A human player's owning
  client now makes the transition decision, the server copy mirrors exactly one
  stack removal, and a bot has one server writer. Only the writer uses the
  vanilla authority-aware cooldown route, so one ten-second interval produces
  one mirrored stack rather than owner/server double growth.
- Added an edge-driven two-setting consensus over both **Focused Spirit
  stacking rework** and **Focused Spirit ignores chip damage**. Exact CRT peers
  announce only on parity establishment, a local setting change, or one direct
  reply. Missing, mismatched, stale, contradictory, foreign-epoch, or malformed
  state holds the modification at vanilla; there is no polling or per-frame RPC.
- Kept the authored global talent-description key and moved all four setting
  combinations into CRT's single global `Localize` owner. Chip-only mode retains
  vanilla formatting values and escaped percents; stacking modes clear those
  values and return literal percents, preventing both raw internal keys and
  `<INVALID STRING FORMAT>`.
- Deferred every cooldown request until the enclosing damage call succeeds,
  clears pending transition state on setting changes and disable, and exposes
  bounded role/action/stack/cooldown receipts plus the read-only
  `/crt_verify_focused_spirit` command.
- Isolated the Focused Spirit definition in its own hook-neutral catalogue
  fragment, keeping the generic early catalogue below its frozen size while
  the composer continues to reject duplicate setting ownership.
- Lua 5.1 coverage models five complete growth intervals, hits at zero/one/
  three/five stacks, every preservation boundary, host/remote/observer/bot
  roles, both setting bits, peer departure, stale and contradictory generations,
  foreign epochs, malformed payloads, and throwing readers/transports. The
  unchanged #334 classifier suite remains part of the full gate.

Runtime success is not claimed by this code/build record. Use the exact
published solo card first. Changing either Focused Spirit setting requires a
talent reapply or mission reload; reversed-role co-op follows only after solo
behavior and all four descriptions pass.

## 0.4.23-beta (2026-08-21) - Dance of Blades pair stacks and server authority (#473)

- Repaired the Dance of Blades stack shape to use two distinct local
  `BuffExtension` bucket identities. One hostile hit can now add one outgoing
  damage stack and one incoming-damage stack through hit fifteen; hit sixteen
  adds neither. The cap is the requested `+30% damage dealt / +30% damage
  taken`, rather than the prior shared-name ceiling of `+16% / +14%`.
- Made the `on_hit` proc server-authoritative. A client-owned Handmaiden no
  longer writes once on the owning client and again when the host receives
  `rpc_buff_on_attack`; host, forwarded-client, and bot hits each have one
  authoritative writer, and the existing peer-parity wrapper remains the final
  custom-buff send gate.
- Preserved the exact three network-visible top-level buff names and their
  registration order. The two new semantic sub-buff names stay local and add no
  `NetworkLookup` row, RPC, hook, or update loop. The native blocking-dodge
  branch and its dodge-distance/speed buffs are unchanged.
- Strengthened `issue473_dance_of_blades_contract` against the installed live
  templates. Lua 5.1 coverage now models the engine's name-keyed cap, staggered
  pair expiry, host/client/bot authority topologies, parity closure, and planted
  versions of both deployed defects.

Runtime success is not claimed by this code/build record. Verification follows
the exact published release card after canonical publication.

## 0.4.22-beta (2026-08-09) -- peer-parity install becomes a committed transaction (#371, #1158) [untested]

- The shared peer-parity library installs as an atomic transaction: receiver
  and update wrapper commit together inside one guarded call, a partial
  install is terminal for the session (never retried, every floor stays
  shut), and install() reports a commit boolean this mod's gates consume.
- New all_peers_have(mod_id) registry answers cross-mod parity queries and
  fails closed for unknown or uncommitted mods (OOP_REFACTOR_PLAN WS1.5).
- The runtime gate and composite floor now consume the real commit verdict.

## 0.4.21-beta (2026-08-09) - authoritative paths behind composite wire floor (#1158) [untested]

- Every authoritative parity read (balance apply/restore, tourney, the
  rpc_add_buff receiver, GUT grey-out) now routes through a composite floor:
  transport install verified via is_installed, exact buff catalog proven in
  BOTH lookup directions, and settled peer state - with per-send paths keeping
  the stricter live roster check so a just-joined non-crt peer is never sent a
  modded buff name inside the settle poll window.
- Runtime-gate registration is pcall-hardened, falls through gut_dev to gut,
  and is capped at 30 bounded retries; floor predicates moved to
  _crt_wire_policy.lua as pure functions with offline behavioral tests and a
  source lock preventing re-collapse of the live guard.

## 0.4.20-beta (2026-08-06) - exact shared buff-catalog proof (#776, #1158)

- Replaced CRT's private parity transport adapter with the shared peer-parity
  library's opt-in exact mode and a shared deterministic wire-catalog builder.
- Schema 3 proves the exact owned `NetworkLookup.buff_templates` name/index
  catalog, binds every reply to the current challenge and peer epoch, and
  retires bounded disconnect epochs so delayed acknowledgements cannot revive
  an old session.
- Kept the unconditional sender substitution, hot-join filtering, and receiver
  collision floor. Exact proof permits CRT-owned numeric buff traffic; it never
  replaces those fail-closed boundaries.
- Added an optional Mod Tweaker runtime gate over the exact nine
  `networked_unsafe` setting rows (eight balance reworks and one Tourney aura).
  Closed parity makes those rows read-only/grey without changing their saved
  values; the existing gameplay gate remains authoritative when GUT is absent.

## 0.4.19-beta (2026-08-06) - complete the balance-owner decomposition (#1159, #504, #2)

- Extracted the unchanged `BALANCE_MODS` definitions into two dependency-injected, hook-neutral catalogs below the 2,500-line hard limit. `_crt_balance_catalog.lua` composes their disjoint setting owners and rejects collisions; the entry explicitly supplies its mod, wire policy, stub helpers, and THP floor while retaining hook order, apply/restore transactions, and lifecycle ownership.
- Reduced the balance entry from 3,888 to 910 gate-measured lines and marked its decomposition contract complete below the 1,500-line standard. The contract now requires the catalogue, hook, and Foot Knight owners.
- Updated source-contract tests to consume the entry and both catalogs together, preserving every existing runtime assertion without reintroducing monolithic ownership.

**Behavior:** structural-only; settings, defaults, buff data, hook cardinality, network behavior, and persistence are unchanged.

## 0.4.18-beta (2026-08-02) - refresh Feel Nothing on repeated Holy Fervour (#999)

- Added an opt-in Zealot toggle that makes a second Holy Fervour activation
  restart Feel Nothing's five-second duration while the buff is already active.
- Uses the native `max_stacks = 1` plus `refresh_durations = true` behavior on
  the existing vanilla buff; it adds no replacement buff, RPC, timer, or update
  loop, and restores the exact original field when disabled.
- Updates the live talent description and adds offline/runtime regression
  coverage for the authored patch and the active five-second buff shape.

## 0.4.17-beta (2026-08-02) - #472/#699 readiness and #473 hit-trigger change

### Focused Spirit retained-state diagnostics and talent text (#472)

- Replaced the misleading numeric-only Focused Spirit tooltip patch with a full,
  reversible talent description for the stacking behavior: empty start, one 5%
  power stack per ten seconds, five-stack/25% cap, one stack lost per ordinary
  hit, and the separate chip-damage exemption's interaction.
- Added a log-only, transition-deduplicated `[crt:472]` receipt at the actual
  `PlayerUnitHealthExtension.add_damage` -> Focused Spirit proc boundary. It
  records source/type classification, talent detection, ignored/real-hit action,
  stack and cooldown before/after state, and wrapped-call success. The stream is
  hard-capped at 48 distinct transitions and adds no update loop or network data.
- Hardened `/crt_regression_test` so #472 now requires the bounded live receipt
  owner and the reversible full-description lifecycle instead of passing on the
  mere presence of dormant wrapper functions.
### Foot Knight HUD icon semantic ownership (#699)

- Removed HUD icons from the always-on heavy-immunity mechanic and Rock dodge
  penalty. Those are persistent implementation/tradeoff states, not conditional
  aura bonuses; showing borrowed invulnerability art made the former appear to
  be Sienna's **Numb to Pain** effect.
- Kept resident Foot Knight artwork only on the conditional Rock shield-power
  bonus, conditional Teamwork great-weapon power bonus, and timed Final March.
  Their gameplay, lifetime, local-only ownership, and #663 aura reconciliation
  are unchanged.
- Hardened `[crt:699]` to report each state's semantic role, intended icon,
  actual BuffUI widget icon, atlas material/UV identity, semantic match, and an
  explicit Numb-to-Pain collision verdict. Offline tests prove the three visible
  icons occupy atlas coordinates distinct from Numb to Pain and that bookkeeping
  buffs cannot regain a HUD icon unnoticed.

### Dance of Blades triggers on enemy strikes (#473)

- Changed the rework's stack trigger from killing an enemy to striking an enemy,
  matching the verified player-requested behavior while retaining independent
  two-second stack lifetimes, the 15-stack cap, and the blocking-dodge branch.
- Updated the setting and live talent descriptions so they no longer claim that
  a killing blow is required. Later exact-source review found that this version
  was not a valid #473 verification candidate: its two effects shared one
  name-keyed cap and its no-authority proc ran on both client and server. Both
  defects are repaired in 0.4.23-beta.

## 0.4.16-beta (2026-07-26) - #936 split Tourney balance controls [verify-fix]

- Split the 17 legacy career-wide Tourney Balance Testing toggles into 46 independent `[TB]` mutation leaves inside each career's existing Talent Reworks section. The stable legacy IDs remain as changed-only **Enable All** presets, and existing saved ON presets expand to their leaves once on first mission entry.
- Added a third **Enable All Reworks** preset that selects both the Ensrick and Tourney families. Cross-family conflicts now suppress only the exact overlapping Tourney leaf, leaving unrelated Tourney changes active.
- Reconciled the two mutation engines restore-first: Tourney restores its older snapshot, Ensrick applies its selected values, and then non-conflicting Tourney leaves apply. This prevents stale Tourney state from overwriting a newly selected Ensrick value during live setting, master-preset, mission-state, or parity transitions.
- Preserved the peer-parity gate on the network-unsafe Warrior Priest Prayer of Flight leaf, added concise `[TB]` ownership labels and per-leaf descriptions, and extended offline/runtime regression coverage for catalog ownership, migration, changed-only writes, exact-nil restore, conflict precedence, and stale-snapshot transitions.

**Co-op verify candidate:** with matching Career Tweaker versions on host and client, enable individual `[TB]` leaves and confirm unrelated leaves remain independent. Exercise overlapping Ensrick/Tourney choices in both orders, including master presets, and confirm Ensrick wins only at the exact conflict while the prior owner restores cleanly. Verify legacy ON presets expand once, Prayer of Flight remains parity-gated, toggling everything off restores vanilla values, and `/crt_regression_test` passes.

## 0.4.15-beta (2026-07-22) - #935 Foot Knight secondary-slot concrete UI repair [verify-fix]

- Repaired the #619 secondary-melee regression on the controller inventory used by the attached log. The log proves Career Tweaker changed only `CareerSettings.es_knight` to `{melee,ranged}`, then the player opened `HeroWindowLoadoutInventoryConsole`; the prior fix hooked only the separate desktop `HeroWindowLoadoutInventory` category builder.
- Both concrete inventory classes now reconcile the exact `SPProfiles` career object immediately before vanilla caches its item filter. Carrier discovery also uses `pairs` so a sparse modded career array cannot hide Foot Knight after an earlier nil entry. Enabled state preserves both melee and ranged; disabled state removes only Career Tweaker's owned melee insertion.
- Added bounded `[crt:935] menu-slot` evidence, pure Lua coverage for sparse profiles/detached menu careers/deduplication, and runtime coverage requiring every resident inventory surface to have its category hook.

**Solo verify candidate:** play Foot Knight, enable **Melee Weapon in Secondary Slot**, reopen Inventory, and select the lower weapon slot. Confirm both Kruber melee weapons and ranged weapons are listed and equip one of each in turn. Disable the toggle, reopen Inventory, and confirm ranged weapons remain listed while melee weapons no longer appear in the lower slot. Run `/crt_regression_test`; retain `PASS: issue619_foot_knight_contract` and `[crt:935] menu-slot surface=HeroWindowLoadoutInventoryConsole enabled=true slot={melee,ranged} melee=true ranged=true`.

## 0.4.14-beta - 2026-07-19 - #447 revive inert Devotion resolution [untested]

**NOT SHIPPED: awaits issue 625 reconciliation.** crt master is ship-frozen (behind the live Workshop build); this fix lands on master only and cannot reach players until the streams reconcile.

- Fixed the fully inert Devotion replacement (every 2026-07-18 log: `[crt:447] Devotion unresolved candidates=21`, all `display_key=nil`). The resolver localized only `talent.display_name`, a field 18 of the 21 live Zealot talents do not carry; vanilla resolves talent titles via `Localize(display_name or name)` (hero_window_talents.lua:328), so the internal name is the usual title loc key. Candidates now carry that vanilla `display_key`, and the title/description overrides register under it.
- The resolver reads raw loc data per candidate, treats the engine's `<key>` unknown-key wrapper (localization_manager.lua:3-5) as unresolved, and accepts a match only when EXACTLY ONE candidate resolves to the Devotion identity - a duplicated localized title can never retarget an arbitrary talent.
- The `[crt:447]` census now always reports `census candidates=N resolved=N unresolved=N matches=N` before the verdict line; a healthy boot must show `candidates=21 resolved=21 unresolved=0 matches=1` followed by `resolved Devotion internal=... title=Devotion`. Failure keeps the `Devotion unresolved candidates=N; feature inert` line plus per-candidate rows with real titles.
- If file-load resolution is inconclusive, the consolidated Localize hook lazily retries exactly once at the first menu localization, when talent and loc data are certainly live.
- Extended `issue447_flagellation_contract` (try_resolve entry point, census presence, zero unresolved titles) and the offline `test_crt_flagellation` suite (retail-shaped candidate table with nil display_name, loc fallback shape, exactly-one-match rule, census counts).

## 0.4.13-beta - 2026-07-19 - #221 deferred menu ownership census [diagnostics-armed]

- Re-arms the dormant Career Tweaker family audit as a bounded, read-only startup census and `/crt_umbrella_audit` command.
- Reports whether the whole deferred family is present, how many of its four cluster gates are active, and proves `mutation=false`; it installs no gameplay hook and changes no setting.
- Adds public-beta, command, documentation, and regression contracts so the diagnostic cannot silently become a partial master-toggle implementation.

## 0.4.12-beta - 2026-07-19 - #699 Foot Knight HUD icon identity diagnostics [verify-fix-coop]

- Replaced the generic power-increase art on the Rock shield-power and Teamwork great-weapon buffs with the exact resident icons for Rock of Reikland and That's Bloody Teamwork. Both Rock effects now share their talent's authored identity; Teamwork no longer reuses Rock's generic power art.
- Added a bounded automatic `[crt:699]` census at effect transitions. It reports the active sub-template and icon, live atlas residency, vanilla BuffUI widget/icon result, active-widget count and total pool capacity, plus stock UI Tweaks/HideBuffs hidden-or-priority disposition. It follows BuffUI's own local-or-spectated unit selection so a host can diagnose a spectated bot, remains read-only and silent while state is unchanged, and is hard-capped at 64 rows per session.
- Extended offline and `/crt_regression_test` coverage with `issue699_foot_knight_icon_census`, including the 0.25-second throttle and exact vanilla talent-icon keys.

**Solo diagnostic:** play Foot Knight and activate each rework condition. The matching HUD icon should use the talent's own art. If an icon is absent, retain the `[crt:699]` line: `atlas=false` identifies residency, `widget=false` with `hud_widgets` equal to `hud_capacity` identifies capacity, and `hidden=true` or `priority=true` identifies UI Tweaks routing. A host may also spectate a Foot Knight bot; `subject=spectated` proves the census followed the same unit as BuffUI.

**Full acceptance is co-op:** repeat as a client Foot Knight to cover the client's local-owner reconciliation path, then have the host spectate a Foot Knight bot. Preserve #663's two-Foot-Knight no-flicker behavior. This issue therefore requires `verify-fix-coop`, not the mutually exclusive solo label.

## 0.4.11-beta - 2026-07-19 - #728 refresh the live career picker [verify-fix-coop]

- Moved career-unlock ownership into one module that preserves vanilla's four
  return values and continues to respect DLC ownership and peer reservations.
- Refreshes both the Hero View summary and the in-keep character picker after
  an unlock or level-override setting changes, without requesting or spawning
  a profile during the refresh.
- Reapplies vanilla occupancy after rebuilding the picker and emits bounded
  diagnostics that distinguish a career level lock from another player
  reserving Kruber.
- Added offline contracts covering hook ownership, return preservation,
  no-spawn refresh behavior, reservation safety, and diagnostic bounds.

**Two-player verify:** join a lobby where another player reserves one Kruber
career, enable **Unlock All Careers**, and confirm Kruber's other careers unlock
without making the occupied career selectable. Disable the setting and confirm
the vanilla level locks return. Require bounded `[crt:728]` rows in the log and
no profile request, forced spawn, or repeated per-frame diagnostics.

## 0.4.10-beta - 2026-07-19 - #283 preserve Job Well Done stacks [verify-fix]

- Added one dedicated talent-menu guard owning the desktop/controller
  `on_enter` and `on_exit` pairs.
- Skips vanilla talent reapplication only when the menu closes with an exact,
  valid, unchanged selection; changed or invalid rows delegate to vanilla.
- Removed duplicate hook ownership from the dormant talent-swap module while
  keeping talent casting/transposition unloaded as required.
- Added runtime/offline contracts for unchanged, changed, and invalid close
  paths so other temporary career state is not broadly suppressed.

**Solo verify:** build Job Well Done stacks, open and close the talent menu
without changing a talent, and confirm stacks remain. Then change a talent and
confirm vanilla reapplication still occurs. Run `/crt_regression_test` and
require the #283 talent-menu guard checks to pass.

## 0.4.9-beta - 2026-07-19 - #446 register exclusive radio groups [verify-fix]

- Registered both Career Tweaker mutually exclusive clusters with GUT Dev's
  nested radio-control contract.
- Kept the underlying boolean settings and mutex behavior authoritative, so
  the custom UI remains presentation-only and stock VMF checkboxes remain a
  safe fallback.
- Added localized None/default rows and regression checks for complete group
  registration without re-enabling talent casting or transposition.

**Solo verify:** with GUT Dev `0.2.300-dev`, select each option and None in both
Career exclusive groups, Apply, reopen, and restart. Exactly one bubble should
be active and the corresponding boolean settings must persist correctly.

## 0.4.8-beta - 2026-07-19 - #445 nested masters and authorship prefixes [verify-fix]

- Kept the two whole-family all-on controls together under the dedicated **Talent Reworks > Master Toggles** nested group. Individual rework checkboxes remain in their career groups, so the masters are discoverable without mixing bulk controls into the leaf list.
- Changed every active family leaf from the superseded trailing `[Ensrick's Reworks]` / `[Tourney Balance]` suffix form to the requested leading `[Ensrick]` / `[Tourney Balance]` authorship prefix. No `[Working]`, `[Untested]`, issue number, or other lifecycle metadata is displayed.
- Moved family identity, master IDs, and label-prefix policy into one engine-free metadata owner consumed by runtime, localization, and QA. New rework rows can no longer join the visible family tree without the offline test requiring the matching prefix.
- Extended `issue445_rework_family_masters` to validate the live localized prefix for every runtime-owned family member. Offline coverage now proves exact nested parentage, all visible rework checkboxes, prefix idempotence, bounded bulk writes, and the custom partial-selection state.
- Re-audited #611 against current source and RainReligion's confirmed-working report: WT already uses one per-career/slot/source master as an advanced-options gear parent, with individual children nested beneath it and complete bulk/partial/cross-career regression coverage. No WT behavior was changed in this release.

**Solo verify:** open Mod Tweaker > Career Tweaker > Talent Reworks. Confirm **Master Toggles** is a nested group containing only **Enable all Ensrick's Reworks** and **Enable all Tourney Balance Reworks**. Confirm every individual rework begins with `[Ensrick]` or `[Tourney Balance]`, with no lifecycle/status tag and no trailing family suffix. Toggle each master, then make a partial individual selection and confirm both master indicators are off while the selected leaf stays on. Run `/crt_regression_test` and require `PASS: issue445_rework_family_masters` plus `PASS: crt_mod_tweaker_exclusive_groups_registered`.

## 0.4.6-beta - 2026-07-18 - #776 exact buff-wire identity and timed sync [verify-fix-coop]

- Corrected the initial diagnosis using all three attached client crashes. Each receiver got positive server buff id `12`, `13`, or `9` at numeric lookup id `1574`, which resolved locally to timed `crt_questingknight_impetuous_as`. Vanilla `ProcFunctions.add_buff` can only send server id `0`; the repeated positive ids prove a different server-controlled name collided with the client's process-local CRT lookup assignment.
- Strengthened #425's fail-closed beacon from mod presence alone to exact wire-catalog parity. The fingerprint covers every CRT-registered network name and its actual `NetworkLookup.buff_templates` numeric id. Missing identity, older schema, changed names, changed order, or changed base indices keep all CRT network-unsafe reworks at vanilla.
- Added one unconditional `BuffSystem.rpc_add_buff` receiver floor. A numeric id resolving locally to a CRT template is dropped before vanilla when the sender lacks the exact fingerprint; even an exact peer cannot deliver a positive server id to a CRT template containing `duration`, matching vanilla's explicit server-controlled contract. Unrelated names pass through unchanged, and drop diagnostics are bounded once per reason/template.
- Routed Virtue of Impetuous's attack-speed and power effects through vanilla `add_buff_synced(..., BuffSyncType.LocalAndServer)`. The #425 parity check runs first and dependency failure has no generic RPC fallback. Both effects retain one 20-second stack whose duration refreshes on a later kill.
- Preserved the #425 hot-join replay filter and added offline/runtime coverage for exact and mismatched catalogs, all three observed positive ids, unrelated-host collisions, duration rejection, 20-second expiry/refresh, bounded logging, and one receiver/timed writer.

**Co-op verify:** first run both peers on 0.4.6-beta with Virtue of Impetuous and its rework enabled. Kill repeatedly as host and client; both 20-second effects must apply once, refresh from the latest kill, expire, and neither peer may crash. `/crt_regression_test` must pass `crt_wire_catalog_identity_exact_776`, `crt_rpc_add_buff_receiver_floor_776`, and `crt_impetuous_timed_sync_contract_776`. Then deliberately pair 0.4.6-beta with an older CRT build: the exact-catalog gate must keep networked reworks at vanilla and the 0.4.6 peer must remain connected if an old/colliding numeric id arrives; retain the bounded `[crt:776] rpc_add_buff dropped` evidence.

## 0.4.5-beta - 2026-07-17 - #687 Foot Knight tooltip CTD hotfix

- Fixed a crash-to-desktop when hovering the reworked Foot Knight ROCK/TEAMWORK talent descriptions: the 0.4.4-beta extraction moved the `CRT_DESC_OVERRIDES` enabled-predicates into `_career_tweaker_balance_hooks.lua` but left the `foot_knight_policy` module declaration behind in the catalogue, so the hooks file dereferenced a nil global on first tooltip draw (`attempt to index global 'foot_knight_policy'`). The hooks module now instantiates the engine-free policy module itself, matching `_crt_foot_knight.lua`.

## 0.4.4-beta - 2026-07-17 - #540 balance hook-module extraction [tooling]

- Extracted the hook-only crit policy, talent-description localizer, and hot-join wire filter from the oversized balance catalogue into `_career_tweaker_balance_hooks.lua`. The catalogue remains the single owner of rework definitions and apply/restore state; the extracted module installs the same four hooks once and preserves `mod._crt_hellborgs_crit_hook_installed`.
- Reduced `career_tweaker_balance.lua` from 4,475 to 3,890 lines without changing settings, buff definitions, hook targets, or lifecycle behavior. The package glob already includes the new module.
- Added offline structure coverage that requires the load-once boundary, keeps the hook implementations out of the catalogue, and verifies all four hook targets remain present in the extracted module. Updated Foot Knight description coverage to consume the hook owner explicitly.

## 0.4.3-beta - 2026-07-17 - #663 stable multi-Foot-Knight auras [verify-fix-coop]

- Replaced six source-blind Foot Knight aura drivers with one source-scoped claim coordinator. Vanilla searched the target by buff template alone, so one Foot Knight could remove or suppress the server-controlled instance supplied by another Foot Knight.
- Preserved the intended non-stacking result: the first source creates or adopts one vanilla aura buff, intermediate sources add only ownership claims, and only the final source leaving removes the server buff. No custom buff name, lookup entry, RPC, or per-tick network traffic was added.
- Covered all six live Foot Knight base, distance, and closest-ally aura driver templates that use the source-blind vanilla functions. Live range changes from the existing rework still flow through each driver instance.
- Added bounded transition logging with source, target, template, server buff id, claim count, and reason. Routine aura update ticks stay silent.
- Added engine-free two-source/idempotence coverage, source-structure coverage, runtime regression `issue663_foot_knight_aura_source_ownership`, engine documentation, and BUG_CLASSES class 60.

**Co-op verify:** with two human Foot Knights in one mission, stand together and then move one Foot Knight across the aura boundary while watching the buff bar. The shared Foot Knight aura icon must remain stable while either source is in range and disappear once after the final source leaves. Run `/crt_regression_test` and require `PASS: issue663_foot_knight_aura_source_ownership`; the log may show bounded `[crt:663] aura` transitions but no every-tick churn.

## 0.4.2-beta - 2026-07-17 - #619 Foot Knight live descriptions and secondary slot [verify-fix]

- Corrected Rock of Reikland's rendered description key from the unused `_desc` lookup to the talent's authored `markus_knight_passive_block_cost_aura_desc_2`, and added the authored `markus_knight_damage_taken_ally_proximity_desc_2` lookup for That's Bloody Teamwork!.
- Made Rock's description compose the range and shield-offense toggles on every localization call. Teamwork now describes its 10m ally radius, innate-DR tradeoff, and great-weapon bonuses. Turning all related toggles off delegates to the original localizer, restoring the exact vanilla text in every language.
- Hardened the secondary slot across both canonical consumers: backend `CareerSettings` and inventory-menu `SPProfiles`. The accepted-types array remains mutated in place, menu reopen reconciles its cached filter, and enabled state repairs either missing member so both `melee` and `ranged` remain accepted.
- Added buff-bar feedback using resident vanilla Foot Knight icons. Heavy immunity and Rock's dodge tradeoff stay visible while enabled; Rock shield power and Teamwork great-weapon power appear only while their weapon/ally conditions are active and retain stable stack widgets; Final March shows one timed icon for its 60-second effect. The internal Teamwork DR-cancellation buff remains hidden.
- Added transition-only `[crt:619] secondary-slot` diagnostics plus offline coverage for hot-toggle composition, menu-reopen wiring, exact all-off localization delegation, dual-carrier reconciliation, and the ranged-preservation invariant.

**Solo verify:** toggle Expanded Protective Presence, Rock shield offense, and Teamwork offense individually and together while reopening the Talents screen; require each description to update immediately and exact vanilla text to return when off. Confirm Rock/Teamwork conditional icons appear only with the qualifying weapon and allies, remain stable between 0.2s reconciler ticks, and disappear when the condition ends; trigger Final March and confirm one timed icon remains for its 60-second duration. Enable Secondary Melee, reopen Inventory, and confirm the secondary slot lists and equips both a melee weapon and Kruber's ranged weapons. Disable it and confirm ranged remains equipped/available while secondary melee disappears. Run `/crt_regression_test` and retain the `[crt:619] secondary-slot enabled=true ... {melee,ranged}` line.

## 0.4.1-beta - 2026-07-16 - #367 faster Ranger ale drink [verify-fix]

- Renamed the setting to **Ranger Veteran: Faster Ale Drinking Animation** and made its tooltip state the exact 0.75-second target.
- Changed the target from one second to 0.75 seconds. The stock action remains authored at 1.9 seconds; the rework now derives `anim_time_scale` as `1.9 / 0.75`, so `WeaponUnitExtension` resolves the action lock and first-person/third-person playback through the same scale.
- Added bounded apply evidence with the stock duration, target duration, and resolved scale. Toggle-off and mod-disable still restore the exact previous scale or exact nil absence.
- Strengthened offline duration/localization coverage and updated live runtime check `issue367_ale_one_second_drink` to assert the 0.75-second contract while preserving its registered tester-facing name.

**Solo verify:** enable **Faster Ale Drinking Animation** under Talent Reworks > Ranger Veteran, drink an ale, and confirm the visible drink and control lock end together in about 0.75 seconds and the buff is granted once. Disable it and confirm the stock 1.9-second drink returns. Run `/crt_regression_test` and require `PASS: issue367_ale_one_second_drink`; the log should also contain `[crt:367] applied Ranger ale speed: stock=1.90s target=0.75s anim_time_scale=2.533333`.

## 0.4.0-beta - 2026-07-15 - public beta rollup

- Promoted the tested Career balance and rework line through 0.3.75-dev, including the Foot Knight feature suite, rework-family masters, Ranger ale improvements, Zealot Flagellation, Handmaiden reworks, peer-parity hardening, localization corrections, and retired Big Rebalance cleanup.
- Excluded career talent/ability casting and transposition from this beta. The menu, loader, lifecycle dispatch, status output, and talent-window hooks are absent; saved `talent_swap_*` values are retained without being read, changed, or applied.
- Excluded the open Bardin-disabler and historical umbrella-ownership investigation probes. Their development source remains available, but this beta installs none of their hooks or commands.
- Added runtime regression contracts proving the excluded systems stay inert while ordinary Career balance features remain available.

**Beta verify:** after a full restart, confirm the Career Ability & Talent Swapping group is absent, existing careers and talents remain unchanged on keep/mission transitions, and `/crt_regression_test` reports `PASS: public_beta_talent_swaps_disabled` plus `PASS: public_beta_issue_probes_disabled`. Then exercise the ordinary opt-in reworks relevant to your career.

## 0.3.75-dev - 2026-07-15 - #619 Foot Knight feature suite [verify-fix-coop]

- Added six independent, default-off Foot Knight controls: uninterruptible heavy attacks; 10m Protective Presence with 20m Rock of Reikland; Rock shield offense; expanded That's Bloody Teamwork! great-weapon offense; Final March; and melee weapons in the secondary slot.
- Rock shield offense now carries its requested tradeoff: a toggle-wide 10% reduction to effective dodge distance. With Rock selected and any live shield-capable melee template equipped, it grants 15% power and 30% more melee damage to Monsters and Berserkers. The capability policy includes vanilla's exceptional Flail & Shield type and inherited WT/CWV templates.
- That's Bloody Teamwork! now checks allies at 10m. Its toggle removes only Foot Knight's native 10% damage reduction; aura DR, the talent's existing 5% DR per ally, and Final March remain intact. With a non-polearm great weapon, each of up to three nearby allies also grants 5% power and 10% more melee damage to Armored enemies and Monsters. War Picks count; polearms, glaives, and scythes do not.
- Final March triggers once per mission only after every other ally is truly dead, not merely downed or disabled. It knocks back a current disabler and grants 50% power plus 50% damage reduction for 60 seconds.
- Secondary melee reuses the exact native Slayer/Grail Knight `slot_ranged = { "melee", "ranged" }` contract. The live accepted-types array is mutated in place for existing UI/backend consumers; toggle-off removes only CRT's own member and abandons ownership safely if another mod replaces the array.
- Kept the combat and tradeoff buffs local-only, outside `NetworkLookup`. The server evaluates every player and bot while each client evaluates only its local owner; no custom buff identifier or per-frame RPC was added.
- Added engine-free capability/damage/slot/Final March coverage, singleton damage-hook coverage, and runtime regression `issue619_foot_knight_contract`. The Lua 5.1 suite passes 616 tests.

**Co-op verify:** with host and client on Foot Knight, exercise each toggle separately. Confirm heavy wind-ups cannot be interrupted; aura edges are 10m/20m; Rock shield damage and 10% shorter dodges apply to native plus WT/CWV shields; Teamwork keeps 5% ally DR but removes only innate DR and grants the great-weapon bonuses within 10m; downed/disabled allies do not trigger Final March but three dead allies do once; and a secondary melee survives inventory reopen, mission entry, weapon swaps, bot use, and a Chaos Wastes transition. Toggle every option back off and confirm vanilla values/slot rules return without deleting inventory items. Require `PASS: issue619_foot_knight_contract` from `/crt_regression_test`.

## 0.3.74-dev - 2026-07-14 - #221 historical subgroup-master audit [diagnostics-armed; not deployed]

- Confirmed that #445 already fulfills the safe whole-family Ensrick and Tourney controls requested by the historical menu-consolidation plan.
- Added one bounded, observation-only `[crt:221]` startup census and `/crt_umbrella_audit`. It reports exact whole-family totals plus the Unchained rework/runtime, Outcast Engineer rework, and armor subgroup counts currently crossing separate lifecycle owners.
- Deliberately did not add incomplete subgroup checkboxes. A per-cluster master must gate every hook, template mutation, and restoration owner before it can honestly promise vanilla behavior when off.
- Added pure catalog/count/format coverage and a source/menu drift check. The diagnostic performs no setting writes, template mutations, hooks, RPCs, or lookup registration.

**Diagnostics:** run `/crt_umbrella_audit` and retain the single `[crt:221]` line. Require `whole_family=present`, nonzero totals for the reported live clusters, `cluster_gates=0/4`, and `mutation=false`. The zero gate count is an explicit deferred-boundary signal, not a runtime failure.

## 0.3.73-dev - 2026-07-14 - #367 one-second Ranger ale drink [verify-fix; not deployed]

- Added a default-off **Ranger Veteran: One-second ale drinking** rework. Vanilla's ale action has `total_time = 1.9`; the rework sets its native `anim_time_scale` to 1.9, so `WeaponUnitExtension` resolves both action completion and first-person/third-person playback to one second through the same source-verified scale.
- Preserved the stock `one_time_consumable` finish path, standard ale buff, ammo consumption, animation events, and network RPC. The option changes no buff duration or stack behavior and composes independently with #366.
- The balance lifecycle snapshots whether the template originally had an animation scale and restores either its exact value or exact absence on toggle-off/disable. Unexpected template shapes fail closed.
- Added offline lifecycle/structure coverage and runtime check `issue367_ale_one_second_drink`.

**Solo verify:** enable the option under Talent Reworks > Ranger Veteran, drink an ale, and confirm the animation and control lock both finish together in about one second and the buff is granted once. Disable it and confirm the stock 1.9-second drink returns. Run `/crt_regression_test` and require `PASS: issue367_ale_one_second_drink`.

## 0.3.72-dev - 2026-07-14 - #447 Zealot Flagellation [verify-fix; not deployed]

- Added an opt-in replacement for Zealot's Devotion talent: **Flagellation**. While that talent and any level-5 THP talent are selected, each realized THP gain converts half as much permanent health into THP; four gained THP converts two green health.
- Scoped attribution to the four native proc functions referenced by Zealot's three live level-5 THP templates. The health hook acts only during those synchronous proc windows, so Natural Bond, supplies, career abilities, boons, and unrelated `heal_from_proc` effects do not trigger conversion.
- Vanilla applies and caps THP first. Conversion uses the observed temporary-health delta, caps to remaining permanent health, and delegates to the existing server-authoritative `convert_to_temp` path.
- Resolved Devotion from the live Zealot talent table by localized title rather than hard-coding an identifier absent from the older decompile. If resolution fails after a game update, the feature remains inert and emits a bounded `[crt:447]` candidate census instead of targeting another talent.
- Registered the hook-owned toggle in the native rework catalog so #445's Ensrick family control includes it. Declared the anticipated `zealot_thp_conversions` mutex cluster: Flagellation and the Holy Fervour green-to-THP rework are alternative conversion models and cannot be enabled together.
- Reused Career Tweaker's consolidated Localize hook for the Flagellation title/description. Added no buff, RPC, or `NetworkLookup` entry. Added pure policy/structure tests, runtime check `issue447_flagellation_contract`, `FLAGELLATION_REWORK.md`, and engine-surface documentation.

## 0.3.71-dev - 2026-07-14 - #473 Dance of Blades rework (historical pre-release implementation; superseded)

- Added an opt-in Handmaiden rework for the vanilla `kerillian_maidenguard_versatile_dodge` talent: each kill grants 2% damage dealt and 2% increased damage taken for two seconds, up to 15 stacks (30%/30%).
- Every stack uses its own non-refreshing two-second lifetime. Rapid kills build the requested window; a later kill cannot extend an older stack.
- Preserved the vanilla blocking-dodge branch, including its authored 20% dodge-distance benefit and associated dodge-speed handling. Non-blocking dodges no longer grant the vanilla power reward while the rework is active.
- Used `damage_dealt` instead of generic power so the benefit does not inflate stagger. The vulnerability uses one `damage_taken` stacking bucket, producing a linear 30% at cap rather than compounding 1.02 fifteen times.
- Registered three custom buff names unconditionally in canonical alphabetical order. The kill add routes through the existing live peer-parity wrapper, the entire rework degrades to vanilla when any peer lacks Career Tweaker, and no new RPC was introduced.
- Added reversible talent/template lifecycle, live talent text, pure policy tests, runtime check `issue473_dance_of_blades_contract`, and `DANCE_OF_BLADES_REWORK.md` with co-op verification.

**Historical correction:** the declared 30%/30% cap and verification readiness
were false. Both sub-buffs used the same engine stack-bucket name, and the proc
had two writers for a client-owned Handmaiden. See 0.4.23-beta.

## 0.3.70-dev - 2026-07-14 - #433 remove dead Big Rebalance implementation [not deployed]

- Applied #321's retirement decision to the Career Tweaker portion of #433: deleted the unreachable 133,687-byte `career_tweaker_big_rebalance.lua` implementation. It was never loaded, still contained 27 incomplete bodies, and depended on the retired `bt` registration owner. Historical recovery remains available through git; copying it back is not a supported reactivation path.
- Removed the no-op `big_rebalance` lifecycle stub, dead `^cbr_` setting dispatch, restore/apply/count calls, obsolete status output, and the runtime check that claimed to harden code which no longer executes. Old `cbr_*` values remain untouched in VMF storage and the prefix remains reserved by the retirement gate.
- Preserved the active native and Tourney rework engines and #445 family masters unchanged. Added host-runtime tests for dead-file/stub absence plus live-family retention, and extended `check_retired_big_rebalance.ps1` so the deleted Career implementation cannot silently return to shipped scripts.

**Repository verification:** no in-game behavior was removed because the module had no loader. Require the blocking retirement check, Career Tweaker lint, and Lua unit suite to pass. #433 remains open until the equivalent WT/WT-dev and Enemy Tweaker dead implementations receive their own isolated cleanup/version passes.

## 0.3.69-dev - 2026-07-14 - #445 rework-family master controls [verify-fix]

- Added two live, mutually exclusive family controls under Talent Reworks: **Enable all Ensrick's Reworks** and **Enable all Tourney Balance Reworks**. Enabling one applies its complete active catalog and clears the rival family; turning it off clears only that family. Partial individual selections are a valid custom state and leave both masters off.
- Bulk selection is bounded: nested VMF callbacks are suppressed while changed leaf settings are written, then the native-rework and Tourney owners each apply once. The plan writes only values that actually changed and logs one compact `[crt:445]` summary.
- Every active leaf title now derives a `[Ensrick's Reworks]` or `[Tourney Balance]` suffix from its stable setting prefix. Groups, tooltips, and master rows remain concise. Retired `cbr_*` entries are neither revived nor used as a master dependency.
- Replaced #446's hidden retired-BR demonstration cluster with the two visible family controls. The stock VMF menu is enforced by crt itself; Mod Tweaker also receives the same mutex pair through its existing data-driven exclusive-group API.
- Offline coverage proves complete-family/rival clearing, custom-state preservation, exact master indicators, suffix completeness, plain-checkbox widget wiring, and write de-duplication. Runtime check `issue445_rework_family_masters` validates the live catalogs and mutex declaration.

**Solo verify after deployment:** open Career Tweaker in Mod Tweaker. Under Talent Reworks > Rework Family Presets, enable Ensrick's master and confirm its active leaf rows turn on while every Tourney row is off; switch to Tourney and confirm the inverse with an immediate repaint. Turn Tourney off and confirm its leaves clear. Finally enable one individual leaf and confirm both master controls remain off as a custom selection. Run `/crt_regression_test` and require `PASS: issue445_rework_family_masters` plus `PASS: crt_mod_tweaker_exclusive_groups_registered`.

## 0.3.68-dev - 2026-07-14 - #440 Bardin disabler dodge investigation [diagnostics-armed; coop-required]

- **Finding, not a balance fix.** The decompiled Lua provides one shared dodge movement/status path for all five heroes. Packmaster and Lifeleech consume that same dodge status without a profile branch. Bardin's shorter first-person height is camera presentation data and is never read by those paths. No evidence supports changing Bardin's dodge distance or timing.
- **Remaining uncertainty.** Gutter Runner pounces are spatial rather than status-gated: root plus a fixed 0.2m trajectory target, a one-metre player-trigger overlap, then `j_neck` tracking. Character-specific trigger/neck geometry lives in compiled unit assets and cannot be proved equal from the Lua dump.
- **Automatic diagnostics.** Added a read-only probe that records one settings/geometry summary per profile, at most 16 completed local dodges made within 25m of a disabler, and at most 16 outcome rows per disabler. `[crt:440]` rows correlate profile, outcome, live dodge phase/elapsed time/displacement/distance-left, attacker distance, neck height, actor count, and disabler-specific tracking state. Client-local dodge rows align with host-authoritative outcome rows by timestamp without adding RPC traffic. It requires no chat command and changes no gameplay value.
- **Regression/documentation.** Added `BARDIN_DISABLER_AUDIT.md`, offline `test_crt_bardin_disabler_probe.lua`, and runtime `issue440_bardin_disabler_probe`.

**Verify after deployment (two players recommended):** test Bardin and a non-Bardin control with comparable weapons, side-dodge direction and latency against repeated Packmaster hooks, Lifeleech grabs and Gutter Runner pounces. Attach the log containing `[crt:440]` rows. A Gutter-only separation with comparable dodge timing points toward compiled trigger/neck geometry; missing/late dodge status points toward timing/network input. Do not infer a balance fix from one attempt.

## 0.3.67-dev - 2026-07-14 - #366 stagger Ranger Veteran ale expiry [verify-fix]

- Added an opt-in Ranger Veteran rework that gives both ale effects independent per-stack lifetimes. Vanilla sets `refresh_durations = true` on the damage-reduction and attack-speed sub-buffs (`buff_templates.lua:5323-5343`), and `BuffExtension._add_stacking_buff` consequently refreshes every existing stack before adding the next (`buff_extension.lua:520-533`). The rework sets that field false on both sub-buffs, preserving each drink's own authored 300-second clock.
- Extended the reversible balance patch engine with `sub_index` (default 1), so multi-sub-buff templates can be targeted without custom mutation code; all existing patches retain their original index-1 behavior.
- Added runtime check `issue366_ale_independent_stack_decay` plus offline coverage for the two-index contract and all apply/restore paths.
- **Solo verify after deployment:** enable **Ranger Veteran: Ale stacks expire independently**, collect three ales at visibly staggered times, and confirm the HUD drops from three stacks to two to one at those same staggered five-minute expiry points. Later ales must not make the earlier stacks expire together.

## 0.3.66-dev - 2026-07-13 - #283 preserve accumulated buffs when merely viewing talents [not deployed]

- Source audit corrected the suspected cause: both vanilla talent windows unconditionally call `TalentExtension:talents_changed()` on close (`hero_window_talents.lua:53-74`; controller equivalent `hero_window_talents_console.lua:67-88`). That method calls `apply_buffs_from_talents`, which clears every prior talent buff before rebuilding it (`talent_extension.lua:48-62,78-101`), so opening and closing the menu erases accumulated state even when no talent changed.
- Desktop and controller talent windows now snapshot the selected talent rows on entry. If the rows are identical on exit, crt performs only vanilla's animator teardown and skips the no-op backend write, talent rebuild/sync, and ammo-buff reapply. Any actual row change delegates to the complete vanilla path unchanged.
- Offline tests lock exact, changed, sparse, and invalid selection comparisons. `/crt_regression_test` adds `issue283_talent_menu_noop_guard` to prove the guard installed and its runtime decision boundary is live.
- **Solo verify after deployment:** as Bounty Hunter with Job Well Done, build several stacks, open and close Talents without selecting anything, and confirm the stacks remain. Reopen, change one talent, close, and confirm the normal talent reapply still occurs.

## 0.3.65-dev - 2026-07-13 - #472 Handmaiden Focused Spirit exclusions and stacking rework [not deployed]

- Added a default-ON Focused Spirit exemption for the same source-verified chip classes used by #334: generic `dot_debuff`, poison/warpfire/AOE damage types, self `wounded_dot`, plus Ratling projectile sources (`skaven_ratling_gunner` / `vs_ratling_gunner`). Ordinary enemy hits still reset the talent. The full `damage_source_name` is captured in the existing `PlayerUnitHealthExtension.add_damage` hook because the vanilla Focused Spirit proc receives only attacker, amount, and damage type.
- Added an opt-in stacking rework: Focused Spirit starts empty, gains one 5% power stack after each vanilla ten-second no-damage cooldown, caps at five stacks, and an ordinary hit removes exactly one stack and restarts the timer. It reuses only the two vanilla Focused Spirit buff names; no modded NetworkLookup entry or new RPC is introduced.
- Moved #334's exact chip/self-DoT predicates into the pure `_crt_damage_classification.lua` manifest module. Offline tests lock its old boundary and the new gas, warpfire, Ratling, and ordinary-hit cases. `/crt_regression_test` adds `issue472_focused_spirit_contract` for the reversible patch catalog and proc/update wiring.
- **Solo verify after deployment:** equip Focused Spirit. With the exemption ON, confirm Unquenchable Thirst, Nurgle's Rot, gas, Warpfire Thrower, and Ratling damage do not reset it, while a normal melee hit does. Then enable the stacking rework, reload Handmaiden, wait through five ten-second windows for 25% power, and confirm each ordinary hit removes one stack rather than all five.

## 0.3.64-dev - 2026-07-13 - #321 retire stale Big Rebalance product surface [not deployed]

- Confirmed the professional retirement path: the BR module stays replaced by its no-op lifecycle stub and the `cbr_*` widget/localization catalogs stay hidden. Reactivation is rejected while 27 archived bodies remain unimplemented and no shared registration owner exists.
- Removed obsolete Big Rebalance claims from the Workshop description. Existing saved `cbr_*` values are intentionally preserved but never read, avoiding destructive migration and identifier reuse.
- Added a blocking cross-mod QA contract and migration/ownership documentation. Tag `[verify-fix]`; verify solo that the Big Rebalance group is absent.

## 0.3.63-dev - 2026-07-13 - #458 transition-safe shared peer parity [not deployed]

- The shared parity beacon preserves a positive same-peer acknowledgement across a bounded 15-second PlayerManager roster absence during level transitions and delays missing-peer chat for 10 seconds. New, expired, or never-confirmed peers remain fail-closed immediately; this removes the observed false disable/re-enable chat cycle without relaxing wire safety.

## 0.3.62-dev - 2026-07-13 - #427 _dbg_alert log-only via engine printf [untested]

- `_dbg_alert` rerouted mod:warning -> pcall-guarded engine printf (VMF warning channel posts to chat under default settings; printf survives mod-logging-OFF, never chat; enemy_tweaker issue 240 template). `career_tweaker.lua` only; `mod._crt.dbg_alert` export unchanged.

## 0.3.61-dev - 2026-07-13 - #443 talent rework descriptions rewritten to vanilla style; factual corrections [untested]

### Why
Issue #443: the AI-written in-game talent descriptions for the reworks were improper - they restated
the talent title in the body, used +/- signs, parentheses, and dash asides, ran past 2 sentences,
and told the player which effects the mod moved to innate perks (e.g. the Salvaged Ammunition
reload-on-melee-kill). The issue defines 10 style rules; every entry in the `CRT_DESC_OVERRIDES`
Localize table now follows them.

### Changed
- **Every talent-description override in `career_tweaker_balance.lua` rewritten** (~38 entries): max 2
  sentences, no title restated, no +/- or bracket characters, literal numbers, no innate-perk
  bookkeeping in player-facing text.
- **Factual corrections found while re-reading each implementation** (details in the issue):
  - Salvaged Ammunition: Elite kills restore **20%** of max ammo (vanilla `ammo_bonus_fraction = 0.2`),
    not 5%, and the restore is not melee-gated. Stale code comment fixed too.
  - Just Reward: names the real effect - ranged crits refund **20%** of Locked and Loaded's cooldown,
    once every 5 seconds (option tooltip previously said "ammo refund").
  - Castigate: stacks per **30 missing health**, not per Fiery Faith stack (title + talent text).
  - Fuel for the Fire: Sienna **gains 5% power per enemy hit** by the Career Skill (15s, 5 stacks);
    old text claimed enemies take increased damage.
  - Famished Flames: buffs **burn damage over time**, not damage taken by burning enemies.
  - Flame Unending / Abandon perk: described as faster **recharge** (`cooldown_regen`), not a flat
    cooldown cut; Abandon perk text now notes the health cost at high overcharge.
  - Virtue of the Impetuous Knight: movement speed keeps its **ability-kill-only** trigger; only the
    new attack speed / power procs fire on any kill (talent text + option tooltip).
  - Full Head of Steam: flat 4% attack speed **while at maximum pressure** (max_stacks 1), not per
    pump stack (title, option tooltip, talent text).
  - Ricochet: applies to **all arrows** and has **no friendly-fire exemption** (no such hook ever
    shipped) - "(no FF on bounces)" removed from the option title, code comment corrected.
  - Death Ascendant: single refreshing buff (max_stacks 1), not "stacks", in the option tooltip.
  - Trophy Hunter rework text now says **melee** damage (`increased_weapon_damage_melee`).
- **Unstable-Strength-linked descriptions resolve live**: Numb to Pain, Natural Talent, and Flame
  Unending texts are now functions picking 5%/10% vs 6%/12% per the rescale toggle (the shared
  Localize hook resolves `type(text) == "function"` per call).
- Loc hygiene: "Rock of the Reickland" misspelling removed from the option tooltip; Leading Shots
  loc mirror matches the live override text.

## 0.3.60-dev - 2026-07-12 - #405 post-fix pass: regression marker for the Fires-from-Ash heal gate [untested]

### Changed
- **#405 (client CTD "Only server can heal"): the shipped is_server gate on the Fires-from-Ash THP proc heal now sets a load-time marker** (`mod._crt405_heal_is_server_gated`, career_tweaker_balance.lua beside the gate), asserted by the new `/crt_regression_test` check `issue405_heal_network_is_server_gated` - a reverted gate fails the suite. Runtime marker per the issue 511 doctrine (no source self-read). This was the last owed post-fix-pass pillar for issue 405 (hardening + BUG_CLASSES section 29 already in place).

## 0.3.59-dev - 2026-07-12 - #446 register same-talent rival groups into Mod Tweaker [untested]

### Why
Part 2 of #446. gut_dev 0.2.222-dev shipped the data-driven "mutually-exclusive group" API
(`get_mod("gut_dev").mod_tweaker:register_exclusive_group`); crt is the first consumer, so clicking
one member of a same-talent rival cluster ON in the Mod Tweaker menu flips the siblings OFF with a
row repaint. Best-effort enhancement layered on crt's existing on_setting_changed mutex; no hard
dependency on gut.

### Added - #446 (Mod Tweaker exclusive-group registration)
- **crt registers its `mutex.CLUSTERS` same-talent rival clusters into gut's Mod Tweaker exclusive-group
  API** at `on_all_mods_loaded` (`career_tweaker.lua`). Data-driven: every cluster declared via
  `mutex.declare` auto-registers as `crt_<group_id>` with members `{ mod = "crt", setting = <id> }`; no
  per-group code. Today that is `bh_passive_choice` (Ensrick's BH "Job Well Done" passive rework vs Core
  BR's passive-perks rework -- the same passive).
- **The issue's named "Zealot THP Conversions" group is NOT wired: crt implements only ONE Zealot
  THP-conversion rework** (`rework_wh_zealot_ability_green_to_thp`, Holy Fervour converts green HP to
  THP). gut -- like `mutex.declare` -- rejects a solo group (2+ members required), so there is no group
  to form until a second rival THP-conversion rework is added. When that lands and `mutex.declare`s the
  cluster, it auto-registers with zero code change.
- **dev/stable id resolution:** resolves `get_mod("gut_dev")` then `get_mod("gut")`, using whichever
  exposes `.mod_tweaker.register_exclusive_group`. Silent no-op when neither is present.
- **No boot-time reconcile of a pre-existing both-ON state.** Both enforcement layers are
  change-triggered; the registration never `mod:set`s members at load (the UI already prevents both-ON,
  and the gut contract does not prescribe a boot sweep). Enforcement kicks in on the next member toggle.
- **New regression check `crt_mod_tweaker_exclusive_groups_registered`** (`_crt_regression.lua`, appended
  last, frozen order preserved): asserts the registration pass ran and did not partial-fail; on `ok`,
  drives gut's live reverse-lookup to confirm each declared 2+ cluster's first member resolves to its
  `crt_<group_id>`. gut-absent is a valid pass. Runtime-only, no io (issue 511).
- Exposed `mod._crt.mutex` so the rt check can iterate `CLUSTERS` at invocation time. No new `mod:hook`.

## 0.3.58-dev - 2026-07-12 - #506 shared parity-lib ordering fix + crt workaround removal; #507 crt hygiene

### Why
Both items surfaced during the issue 503 ENGINE_SURFACE pass; no user-visible symptom today.
- #506: the shared peer-parity lib (`tools/shared_lib/_lib_peer_parity.lua`, master) fired its
  gated-feature transition callbacks BEFORE writing `_applied`, so a callback that read
  `applied_state()` saw the PREVIOUS state (one transition stale). crt worked around this with a
  private `mod._crt_parity_settled_enabled` mirror flag; cwv and the ct_dev copy did not.
- #507: two code-hygiene items in `career_tweaker_balance.lua`.

### Fixed - #506 (shared lib ordering + crt workaround removal)
- **Master lib `_apply` now commits `_applied` BEFORE invoking callbacks**, so a callback reading
  `inst:applied_state()` (and the late-registration coherence path) observes the transition it is
  part of. Callbacks stay pcall-wrapped, so `_applied` is committed regardless of a callback error
  (identical to the prior trailing write). Re-copied verbatim into the crt-local copy. (The cwv copy
  ships in its own v0.1.382-dev bump; the `chaos_wastes_tweaker_dev` copy is outside this pass's scope
  and still needs the identical re-copy.)
- **Removed crt's `mod._crt_parity_settled_enabled` workaround.** The gated-feature callbacks
  (`career_tweaker.lua`) no longer set the mirror flag; `_crt_parity_gate_ok` (balance) and the tourney
  apply engine now read `mod._crt_peer_parity:applied_state() == "enabled"` directly (nil beacon ->
  vanilla/inert, same fail-safe as before). Behavior is identical; the read is now correct from inside
  a transition callback because of the master fix.
- **New regression check** `crt_parity_applied_state_committed_before_callbacks`: builds a throwaway
  (never-installed) beacon instance, registers a probe feature, drives a solo enable, and asserts the
  callback observed `applied_state() == "enabled"`. Locks the ordering the workaround removal depends on.

### Fixed - #507 (crt hygiene)
- **Salvaged Ammunition comment corrected (it was NOT a dead save).** `_orig_salvaged_ammo_fn` is the
  LIVE toggle-off delegate the wrapper calls on every proc when the rework is off (the default). The
  old comment mischaracterized it as a never-wired shutdown-restore handle; rewritten to describe the
  real delegate use. No code change (deleting the variable would crash the default-config BH proc).
- **Hellborg's Tutelage crit hook install tripwire.** The `ActionUtils.get_critical_strike_chance`
  table-form hook is guarded by an at-load presence test (table-form cannot hook a nil target; the
  engine-doc convention keeps table-form for plain-global targets). It now records the install
  decision in `mod._crt_hellborgs_crit_hook_installed` and logs a printf warning on the skip branch,
  and a new regression check `crt_hellborgs_crit_hook_installed` fails loudly if a future load-order
  shift ever skips it (was silent feature-loss).

### Refs
issue 371, issue 425 (peer-parity framework), issue 503 (surface pass).

## 0.3.57-dev - 2026-07-12 - Phase 1 OOP decomposition of the entry file (structural, no behavior change)

### Why
`career_tweaker.lua` had grown to 1332 lines, mixing the talent-swap engine, the read-only
diagnostics harness, and the ~500-line /crt_regression_test suite into the entry alongside the
lifecycle callbacks and the issue-425 beacon install. Per PROJECT_STANDARDS 2.2a (the event_tweaker
module-split template) the entry should be a manifest + lifecycle surface, with each concern in a
single-responsibility module.

### Changed - three concerns extracted from the entry into `_crt_*` modules
- **`_crt_talent_swap.lua`** (new) - the career talent-tree + ability/passive swap engine: the
  `HeroWindowTalents` on_enter/on_exit hooks, the DLC ownership gate, `restore_talent_swaps` /
  `apply_talent_swaps` / `refresh_talent_ui`, and the `_ALL_CAREERS` list. Exports through
  `mod._crt` (`apply_talent_swaps`, `restore_talent_swaps`, `refresh_talent_ui`, `ALL_CAREERS`,
  and get/set accessors for the pending-swap table the regression harness probes).
- **`_crt_diagnostics.lua`** (new) - read-only talent/buff diagnostics: `/crt_dump_talents`, the
  reusable `mod.crt_dump_career_talents` body, and the per-session auto-dump harness for reworked
  careers. The per-frame retry pump is now `mod._crt_dump_retry_tick(dt)`, driven by the entry's
  single `mod.update` (which still also drives the OE cooldown tick).
- **`_crt_regression.lua`** (new) - the entire `/crt_regression_test` harness and all 19 check
  bodies, in their frozen registration order (the in-game output order is unchanged). Loads LAST so
  its checks can capture `mod._crt.balance`, the talent-swap restore path + accessors, the `_dbg`
  helpers, and `MOD_VERSION`. Exports `mod._crt.rt_register` so a future phase can distribute checks
  into their owning modules without moving the harness again.
- The entry keeps MOD_VERSION, the boot banner/fingerprint, the module dofile manifest, the mutex
  cluster, the Character XP-level override + Unlock-All-Careers hooks, the 2026-06-21 ability-swap /
  career-select bug-fix hooks, the lifecycle callbacks (`on_game_state_changed` / `on_setting_changed`
  / `on_disabled` / `update`), `ct_status`, and the issue-425 peer-parity beacon install. 1332 -> 568
  lines.

### Not changed - `career_tweaker_balance.lua` left intact this phase
- The issue-425 wire-safety subsystem is NOT a cleanly separable block: the `network_unsafe` tags are
  woven through the BALANCE_MODS rework data across the 4000-line file, and `_crt_parity_gate_ok` /
  `_crt_wire_parity_live` are consumed by the core `apply_balance_mods` engine (which must stay with
  that data) as well as exported. Extracting only the wrapper functions would split a tightly-coupled
  parity subsystem across two files with bidirectional `mod._crt` plumbing, increasing coupling.
  Balance decomposition is deferred to a later phase.

### Verification
- Pure structural move: log/printf strings byte-identical, hook set identical (one hook per
  (Class, method) mod-wide - lint PASS, 24 hooks), command names identical.
- `tools/mod-lint/lint-mod.ps1 -Mod career_tweaker`: PASS (13 files, 0 duplicate-hook / forward-ref /
  late-local / save-restore / network-bound issues).
- VMB build: OK (4 bundles). All three new lua resources confirmed present in the compiled lua
  bundle by murmur64 name-hash (PROJECT_STANDARDS 2.2a rule 8).
- `/crt_regression_test` suite: all 19 checks still register; the one rewired check
  (`on_disabled_unwinds_talent_swaps`) reaches the moved restore path through the new
  `mod._crt.get/set_talent_swap_originals` accessors - same assertion, structurally.

## 0.3.56-dev - 2026-07-12 - Cursed Armor chip exemption no longer swallows other on_damage_taken procs (IMPROVEMENT_BACKLOG P0) [untested]

### Why
The Necromancer Cursed Armor chip/self-DoT exemption (toggle `armor_gromril_ignore_chip`) worked by
temporarily REPLACING the victim's `be.trigger_procs` for the wrapped `add_damage` call and early-
returning on event `"on_damage_taken"`. That killed the counter's own remover proc, but it also
swallowed EVERY other buff's `on_damage_taken` proc for that tick (the file admitted this at the
old `:294-296`). Any career/talent/boon proc keyed on `on_damage_taken` (e.g. stacking-DR removers,
Numb to Pain, Exuberance) silently failed to fire whenever an exempt chip/self-DoT tick landed on a
Necromancer carrying a Cursed Armor counter — a silent gameplay correctness defect.

### Changed - per-proc ProcFunctions wrapper instead of a per-call trigger_procs replacement
- The engine resolves a proc's function BY NAME from the writable global `ProcFunctions` at fire
  time (`buff_extension.lua:1351`), and `buff.buff_func` is snapshotted from the template at add
  time (`buff_extension.lua:421-423`). So at mod load we now re-point ONLY the Cursed Armor
  counter-remover template's proc entry (`BuffTemplates.sienna_necromancer_5_2_counter_remover`
  `.buffs[1].buff_func`, `talent_settings_shovel.lua:347-360`) from the generic `"remove_buff_stack"`
  to a crt-owned `ProcFunctions.crt_cursed_armor_counter_remover` wrapper.
- The wrapper delegates to the vanilla `ProcFunctions.remove_buff_stack` (`buff_templates.lua:3280`)
  unless the victim's current tick is flagged exempt. `add_damage` now sets a per-victim exempt flag
  (`mod._crt_cursed_armor_exempt_unit`, save/restore around the wrapped call) instead of monkey-
  patching `be.trigger_procs`. Result: on an exempt tick ONLY the counter consume is skipped; every
  other `on_damage_taken` proc fires normally.
- Counter behavior preserved exactly: the counter is decremented on precisely the same set of ticks
  as before (all non-exempt `on_damage_taken` ticks) and preserved on precisely the same exempt
  ticks. Proc-function names are never networked (only buff-template names + ids ride `rpc_add_buff`),
  so this is purely local — no NetworkLookup / wire-safety interaction.
- The gromril + overcharge shims (`be.has_buff_type` / `be.apply_buffs_to_value`) are unchanged.
- NEW `/crt_regression_test` check `armor_cursed_armor_procfunc_wrapper`: asserts the wrapper exists,
  the vanilla `remove_buff_stack` delegate target exists, and the counter-remover template's
  `buff_func` is re-pointed to the wrapper (never left as raw `remove_buff_stack` — that would mean
  the `be.trigger_procs`-swallow shape is back).

### Refs
IMPROVEMENT_BACKLOG P0 (`docs/engine/IMPROVEMENT_BACKLOG.md`); `career_tweaker_armor_overcharge.lua`
(old defect at `:299-302`, self-documented `:294-296`). No GitHub issue.

## 0.3.55-dev - 2026-07-11 - Peer-parity gate: networked talent reworks no longer CTD non-crt peers (#425) [untested]

### Why
Eight toggles push MODDED buff names onto vanilla NETWORKED buff paths. Every such path encodes
`NetworkLookup.buff_templates[name]` and sends `rpc_add_buff`; a peer WITHOUT crt has no entry at
that index, so `BuffSystem.rpc_add_buff` fatals on decode (buff_system.lua:430, strict `__index`).
Both directions crash: a crt client's send reaches a non-crt host and is relayed to every other
client (buff_system.lua:419-424); a crt host's send broadcasts to every non-crt client. The
0.3.3-dev unconditional stub registration protects crt-to-crt lobbies only. The wire sweep for
issue 425 found the exposure is SEVEN rework toggles (not the three in the issue body) plus ONE
tourney port caught by adversarial review:
- `rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr` (ProcFunctions.add_buff_on_special_kill, buff_templates.lua:2251-2259)
- `rework_es_questingknight_virtue_of_impetuous_buffed` (ProcFunctions.add_buff, buff_templates.lua:1964-1972, two procs)
- `rework_es_mercenary_enhanced_training_tiered` (own proc -> BuffSystem:add_buff, buff_system.lua:302-307)
- `rework_es_mercenary_blade_barrier_60x_minus_10_on_hit` (ProcFunctions.add_buff)
- `rework_bw_unchained_natural_talent_ranged`, `rework_bw_unchained_abandon_innate_flame_unending`,
  `rework_bw_unchained_numb_to_pain_4x_burn_kill_lose_on_hit` (all three: server-controlled
  overcharge-chunk driver, buff_function_templates.lua:2569, which ALSO replays to hot-joiners
  via BuffSystem.hot_join_sync, buff_system.lua:80-93)
- `trn_wh_priest` (tourney port; the WP 5-2 aura driver activate_buff_on_distance,
  buff_function_templates.lua:2759/2801, grants the mod-registered
  `victor_priest_5_2_speed_buff` as a SERVER-CONTROLLED buff -- broadcast + hot-join replay --
  and the name has NO crt_ prefix, so it also evaded the first-pass prefix-keyed filter)

### Changed - issue 371 gameplay-axis doctrine: inert without peer parity, never a menu toggle
- NEW `_lib_peer_parity.lua` - verbatim copy of the shared beacon (master
  `tools/shared_lib/_lib_peer_parity.lua`, first consumer cwv 0.1.375-dev). VMF-channel presence
  handshake (`crt_peer_parity_present`, schema 1); absence of a reply == peer lacks crt; fail-safe
  inert-until-confirmed; chat notice names the disabled features and the missing peer.
- career_tweaker.lua - beacon instance (`mod._crt_peer_parity`) installed AFTER the existing
  `mod.update` so the lib's preserving wrap keeps the OE cooldown tick + dump retry. One gated
  feature `crt_networked_reworks`; its on_enable/on_disable set the settled flag
  `mod._crt_parity_settled_enabled` FIRST, then re-run the balance AND tourney apply engines.
  The flag exists because the shared lib fires callbacks BEFORE writing its own `_applied`
  state (_lib_peer_parity.lua:215-227), so `applied_state()` read from inside a callback is one
  transition stale (adversarial review finding; latent in the master lib, reported upstream for
  the cwv consumer -- master NOT edited here, another agent owns cwv's lane).
- career_tweaker_balance.lua + career_tweaker_tourney.lua - the eight entries above tagged
  `network_unsafe = true`; both apply engines hold tagged entries at vanilla unless the settled
  flag is set (solo counts as parity; the user's saved setting is never overwritten).
- career_tweaker_balance.lua - four WIRE-SAFE wrappers registered beside the existing crt
  ProcFunctions: `crt_wire_safe_add_buff`, `crt_wire_safe_add_buff_on_special_kill`
  (ProcFunctions), `crt_wire_safe_overcharge_chunks_driver` and
  `crt_wire_safe_distance_aura_driver` (BuffFunctionTemplates.functions).
  The unsafe templates reference the wrappers by name, and the engine resolves proc/update names
  PER CALL (buff_extension.lua:1351 / :794), so even a LIVE buff instance that survived a
  parity degrade consults the live check on every proc - closing the mid-mission hot-join hole.
  Under parity the wrappers delegate to the vanilla functions unchanged; without parity the proc
  wrappers no-op and the driver wrapper strips its own server-controlled stacks (integer-id RPC,
  wire-safe on every receiver).
- career_tweaker_balance.lua - `crt_enhanced_training_proc` degrades its Enhanced-Training branch
  to the EXACT vanilla behavior (gain_markus_mercenary_passive_proc, buff_templates.lua:3537-3542)
  while parity is missing.
- career_tweaker_balance.lua - NEW hook `BuffSystem.hot_join_sync` (pre-flight: no other crt hook
  on BuffSystem): hides mod-registered entries from the server-controlled-buff replay to a joining
  peer, keyed off the new mod-wide registry `mod._crt_mod_registered_buff_names` (crt_* prefix kept
  as belt-and-suspenders) so tourney's vanilla-prefixed names are covered too. The replay fires
  during the join handshake, before any parity ack can exist, so no roster-reactive gate can win
  that race - sender-side filtering is the only safe shape. The wrapped call is pcall'd with an
  UNCONDITIONAL restore (a mid-replay throw must not orphan the stashed entries), then rethrown.
  A crt-running joiner self-heals via the driver's strip/re-add cycle.
- Diagnostics: `[crt:425]` pcall(printf) trail on gate transitions (parity established / degraded),
  wire-guard blocks (once per state flip, no proc-storm spam), parity-skipped rework list, and
  hot-join withholds.
- `/crt_regression_test` - seven new checks: beacon lib/API loaded, fail-safe posture truth table,
  wire-safe wrappers registered (all four + their vanilla delegates), network_unsafe catalog parity
  (balance export vs RT expected seven), no-raw-networked-funcs sweep over the FULL registered-name
  registry (locks future reworks/ports into the wrapper pattern), trn_wh_priest buff_to_add/driver
  pairing lock, hot-join hook target resolvable.

### Behavior notes
- Solo and all-crt lobbies: zero change (wrappers delegate to vanilla functions; gate enabled).
- Mixed lobby: the eight networked entries fall back to vanilla talent behavior for the session
  state and auto-re-enable when everyone has crt (or the non-crt peer leaves). All other reworks
  (local-only buff paths: counter punch, leading shots, waywatcher/zealot/priest passives, double
  shotted, unchained ult burst, numb-to-pain stat stacks applied locally, all field patches on
  vanilla buff names) stay available - vanilla-name field patches can produce cosmetic host/client
  value divergence for non-crt observers but can never crash them.
- Known limitation: non-server-controlled stacks granted BEFORE a mid-mission degrade (e.g. blade
  barrier stacks) linger locally until the next talent re-apply/spawn; they stop growing and cannot
  reach the wire.

### Verify (issue 425, needs a second peer WITHOUT crt)
Full Steam restart first. Non-crt peer joins your lobby; pick a reworked talent from the eight
above; trigger it (kills / overcharge / WP aura). Expected: no crash on either side, `[crt:425]
parity degraded` + chat notice on your side, vanilla talent behavior. Then both peers on crt:
reworks work exactly as before (expect `[crt:425] parity established`).

## 0.3.54-dev - 2026-07-07 - Regression coverage: buff-name registration parity (issue 425)

### Why
The issue-371 wire-safety audit (finding F4) flagged that the crt_* buff-template registration
had no test locking its two load-bearing invariants. The F1 sender-side parity gate itself is
wave-2 work and is NOT touched here; this adds coverage only.

### Changed
- career_tweaker_balance.lua:74 - exposed the canonical registration list as a read-only
  `mod._crt_registered_buff_names` so the regression checks (which live in career_tweaker.lua and
  cannot see the file-local `_CRT_BUFF_NAMES`) can assert against the exact registered catalog.
- career_tweaker.lua - new `/crt_regression_test` check `crt_buff_names_deterministic_sorted`:
  asserts the registration list is strictly ascending (PROJECT_STANDARDS §9.3 - the alphabetical
  order assigns the cross-peer NetworkLookup indices; a reorder or duplicate diverges peers and
  CTDs on rpc_add_buff). Also catches a duplicate name.
- career_tweaker.lua - new check `crt_buff_names_catalog_parity`: asserts the decoupled RT list
  `_CRT_BUFF_NAMES_EXPECTED` matches the real registration list element-for-element and in order,
  so a name added/removed/reordered on one side but not the other fails the gate instead of
  silently validating a stale catalog.

### Notes
- Both checks pass against current code. The F1 non-crt-peer parity gate (the actual crash fix)
  remains pending as wave-2 work.

## 0.3.53-dev - 2026-07-06 - HOTFIX: client CTD on Fires from Ash THP heal (#405)

**Issue 405 [verify-fix] - client hard-crash killing a burning enemy as Sienna Adept with `rework_bw_adept_fires_from_ash_1pct_plus_thp` on:**
- **Root cause (crash block, console-2026-07-07-02.29.14, is_server=false):** the Fires from Ash wrapper (`career_tweaker_balance.lua:3483`) called `DamageUtils.heal_network` unconditionally; that function fasserts "Only server can heal" (damage_utils.lua:2636). Every vanilla `heal_from_proc` call site is gated on `Managers.player.is_server` (buff_templates.lua:325/:404/...) - the wrapper copied the heal but dropped the gate. Host-side play never hits it, which is why 0.3.52 and earlier survived until the first client-side Adept session.
- **Fix:** vanilla gate added before the heal; the client instance no-ops and the host's own proc instance (host also triggers the proc for a client's kill) grants the +0.5 THP when the host runs crt. Vanilla cooldown reduction unchanged on both sides.
- **Verify in-game:** as a CLIENT on Sienna Adept with the toggle on, kill burning enemies - no crash; THP still ticks up when the host runs crt.

## 0.3.52-dev - 2026-07-05 - Fix: Chaos Wastes curse "Unquenchable Thirst" self-DoT eats armor and builds overcharge (#334)

The Chaos Wastes Slaanesh curse "Unquenchable Thirst" (internally `curse_abundance_of_life`) ticks self-damage every 2s through a `custom_dot_tick` that calls `add_damage_network(unit, unit, ...)` with damage_type `"wounded_dot"` and a NIL damage_source (`morris_buff_settings.lua:636-646`). Because the source is nil the tick slips past vanilla's own exemption sets (`INVALID_GROMRIL_DAMAGE_SOURCE` / `INVALID_DAMAGE_TO_OVERHEAT_DAMAGE_SOURCES`, `damage_utils.lua:2114-2127`), so it consumed Ironbreaker Gromril Armour every tick, converted to overcharge under Unchained Blood Magic, and ate a Necromancer Cursed Armor counter. Added an `_is_self_dot` discriminator (damage_type `"wounded_dot"` AND attacker == victim) in `career_tweaker_armor_overcharge.lua` to catch these self-inflicted DoT ticks; the only `wounded_dot` self-tickers are curse / event / mutator DoTs (this curse, skulls_2023, Nurgle's Rot).

### Changed - Gromril + Necromancer Cursed Armor coverage folded into `armor_gromril_ignore_chip`
The existing "Armor ignores chip/DoT/AOE damage" toggle now also exempts self-inflicted curse / event / mutator DoT ticks (Unquenchable Thirst, Nurgle's Rot) from consuming Gromril Armour and Necromancer Cursed Armor counters. Label extended to name curse damage, tooltip gains a curse-coverage sentence, and the status tag moved from [working] to [verify-fix] [Issue 334].

### Added - `unchained_no_overcharge_from_self_dot` toggle (default off)
New Armor & Overcharge checkbox: when on, self-inflicted DoT ticks (the Chaos Wastes curse Unquenchable Thirst, Nurgle's Rot, and similar) no longer build overcharge through Sienna Unchained's Blood Magic passive. Tagged [untested]. Host-authoritative like the other overcharge toggles. Also added a `/crt_regression_test` check (`armor_overcharge_self_dot_toggle_wired`) verifying the new toggle's data widget + both loc keys are present.

## 0.3.51-dev - 2026-07-04 - Localization: apply dev status-tag doctrine (#301)

Localization: applied dev status-tag doctrine (#301). 150 option titles tagged: 149 [working] (2 of them also [diag]), 1 [Issue 283], 0 [untested]. Tags are prefixes on `en` widget-title strings only (group headers, master toggles, checkboxes, dropdowns, numeric fields); tooltips, descriptions, dropdown value labels, and the commented-out Big Rebalance `cbr_*` block were left untouched. `career_swapping_group` carries [Issue 283] (open bug: talent-swap re-apply drops stacking career buffs). `rework_es_mercenary_group` and `rework_bw_unchained_group` carry [diag] (the always-on `[crt:talent]` auto-dump in `_CRT_AUTO_DUMP_CAREERS` targets es_mercenary + bw_unchained). No setting_ids, defaults, mechanics, or display text changed.

## 0.3.50-dev - 2026-07-02 - #222 loc sweep: drop leading option-title restatements

### Changed - tooltip bodies no longer repeat the orange popup header
#222 loc sweep: removed leading option-title restatement from 12 option tooltips so the popup body no longer repeats the orange header (mutex-cluster opener hints preserved). Bodies now open with the behavior. Affected: the two Unchained overcharge toggles under Armor & Overcharge, and ten Tourney Balance career tooltips that led with a "<Career> changes:" preamble. No setting_ids, titles, defaults, or mechanical values changed.

## 0.3.49-dev - 2026-07-01 - Settings menu reorganization (sort + roster order)

Menu SORT / ORGANIZE / POLISH pass only. No settings added, removed, renamed, or re-defaulted; no behavior changes. Verified programmatically: all 179 widget setting_ids and 41 dropdown option values are the same set as 0.3.48-dev, and the commented-out Big Rebalance `cbr_*` block is preserved byte-for-byte in both `career_tweaker_data.lua` and `career_tweaker_localization.lua`.

### Changed - top-level menu order is now A-Z
Reordered the five top-level groups alphabetically by display label: Armor & Overcharge, Career Ability & Talent Swapping, Character Experience Level, Talent Reworks, Tourney Balance (previously accretion-ordered).

### Changed - unified every character grouping on the vanilla hero roster
The four character/career-grouped areas now all follow the vanilla hero roster (Kruber, Bardin, Kerillian, Saltzpyre, Sienna) instead of the two inconsistent orders they had before:
- Talent Reworks character subgroups (was Bardin, Kruber, Kerillian, Sienna, Saltzpyre; General stays first).
- Career Ability & Talent Swapping per-career dropdowns and their shared option lists (was Bardin-first).
- Character Experience Level per-character level fields (was Bardin-first).
- Tourney Balance was already in roster order; unchanged.

A one-line comment above each roster-ordered block names the exemption. Within-character career order and per-toggle order inside a subgroup (both deliberate) were left as-is.

### Changed - polished group labels (display strings only)
Removed redundant / implementation-detail noise from group labels: "Armor & Overcharge (hook-based)" to "Armor & Overcharge"; "Tourney Balance (Careers)" to "Tourney Balance"; the five Tourney subgroups "Kruber (Tourney)" ... "Sienna (Tourney)" to bare character names (they already sit under the Tourney Balance parent). No setting_id or loc key changed.

### Changed - localization file mirrors the widget tree
Reordered `career_tweaker_localization.lua` to match the new widget order with `-- ====` section banners. All 610 keys are unchanged, and every English value is byte-identical to 0.3.48-dev except the 7 group-label edits above.

## 0.3.48-dev — 2026-07-01 — Fix menu localization + rewrite option descriptions

### Fixed — double-localized tooltips showed the sentence wrapped in angle brackets
Widget tooltips were written as `tooltip = mod:localize("key")`, which returned the English sentence at data-load time; VMF then re-localized that whole sentence as a key, missed, and displayed it wrapped in `<...>`. Converted all 24 active widget-level `tooltip = mod:localize("key")` calls in `career_tweaker_data.lua` to raw keys (`tooltip = "key"`) so VMF localizes each once at render time. The top-level mod `name` / `description` eager `mod:localize` calls are correct and were left as-is. (The one such call inside the commented-out Big Rebalance block was also normalized.)

### Changed — rewrote every option description and tooltip for players
Rewrote all option `_description` and `_tooltip` values plus `mod_description` in `career_tweaker_localization.lua` into plain, player-readable English (max two to three sentences each), removing internal jargon (field names, stat ids, dev notes) while keeping game terms, talent names, and balance numbers. Percent signs stay doubled (`%%`) for VMF's format pass. No setting ids, keys, widget structure, or defaults were changed.

### Fixed — non-ASCII / angle-bracket characters in menu strings
Replaced em dashes in three toggle labels (Enhanced Training, Fuel for the Fire, Numb to Pain) with commas, and converted the `->` arrow (which contains a literal `>`) to "to" in 27 rework labels, so no menu string contains `<`, `>`, em dashes, or unicode arrows. Cross-checked every widget-referenced loc key (titles, group headers, tooltip keys, dropdown options) against the loc table: all resolve, none missing.

## 0.3.47-dev — 2026-06-28
- Removed per-mod debug toggle; diagnostics now route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode_debug / output_mode_warning. (#169)

## 0.3.46-dev (2026-06-25) — Fix: Sienna career labels were swapped (Battle Wizard ⇄ Pyromancer)

### Fixed — Talent Reworks menu mislabeled Battle Wizard reworks as "Pyromancer"
The Reworks group `rework_bw_adept_group` and its three checkboxes (Famished Flames, Volcanic Force, Fires from Ash) were labeled **"Pyromancer"**, but `bw_adept` is **Battle Wizard** (`sound_character = "bright_wizard_battle_wizard"`, source `career_settings.lua:1161`); `bw_scholar` is Pyromancer. These reworks patch `sienna_adept_*` talents (Battle Wizard's tree), so the underlying mechanics were always correct — only the display labels were wrong. Relabeled to "Battle Wizard". Display-string-only.

### Fixed — Talent Swap dropdown had the same swap
`talent_swap_bw_scholar` / `talent_swap_option_bw_scholar` said "Battle Wizard" and `talent_swap_bw_adept` / `talent_swap_option_bw_adept` said "Pyromancer" — both inverted. Corrected so the swap-target dropdown shows the right Sienna career names. Display-string-only; setting_id keys unchanged.

Also corrected three misleading `bw_adept = Pyromancer` comments in `career_tweaker_balance.lua` (the original source of the confusion). The `cbr_*` and `trn_*` Sienna groups were already correct and untouched.

## 0.3.45-dev (2026-06-24) — Strip dev-only status tags from public labels

Stripped the dev-only `[untested]` prefix tags from 5 user-facing `en = "..."` label values in `career_tweaker_localization.lua` (the Armor & Overcharge group: Gromril chip/DoT exemption, specials-don't-break-Gromril, Unchained no-overcharge-from-FF/disablers, OE cooldown-reduction benefit). Display-string-only edit — no logic or behavior change. Verified 0 `[untested]` occurrences remain in any `en =` value.

## 0.3.44-dev (2026-06-22) — Unchained: Flame Unending recharge fix + Chain Reaction more/bigger

### Fixed — Flame Unending fed the WRONG cooldown stat
`rework_bw_unchained_abandon_innate_flame_unending` granted **`activated_cooldown`** per Unstable Strength stack — which only trims the cooldown ONCE at activation (cost-gated, one-shot), so it never sped the ability's passive recharge as US stacks built. Switched the per-stack buff to **`cooldown_regen`** (the continuous decay-rate stat; positive = faster) and flipped the sign. Now the career skill recharges progressively faster the more Unstable Strength you hold: **+5% recharge speed per stack up to 6× = +30% at full stacks** with the Unstable Strength rescale on (6% × 5 = +30% on vanilla stacks). Same `activated_cooldown`-vs-`cooldown_regen` distinction as the OE cooldown fix.

### Changed — Chain Reaction ignite now actually spreads + chains
`rework_bw_unchained_chain_reaction_ignite` previously only added the burn DoT. The DoT was real but the explosion radius (0.5–1.5) is HALF the vanilla fire blast (lamp_oil radius 3), so almost nothing caught fire, and the explosion only fired on **40%** of burning kills (vanilla `sienna_unchained_exploding_burning_enemies` proc_chance 0.4). The toggle now ALSO widens the burst to lamp_oil scale (radius_min/max → 1.5/3, max_damage_radius → 1/3) and bumps proc_chance to **1.0** (every burning kill), so the ignite spreads to a cluster and the chain actually chains. Both reverted on toggle-off.

## 0.3.43-dev (2026-06-21) — Unchained #8: give the 10s career-skill Unstable Strength buff a HUD icon

The `crt_unchained_ult_max_us` buff (rework #8: career skill grants max Unstable Strength, +60% melee power for 10s) had no `icon`, so it didn't appear in the buff bar — players couldn't see the 10s window. Added `icon = "sienna_unchained_activated_ability_power_on_enemies_hit"` (the Unchained "Enhanced Power" buff icon) to the buff sub-template (`career_tweaker_balance.lua:3660`), so it now shows in the HUD with its 10s countdown. Data-only; no behavior change.

## 0.3.42-dev (2026-06-21) — Fix: OE cooldown-reduction mirror was a no-op (bonus → multiplier)

The v0.3.41 OE Cooldown-Reduction mirror did nothing in-game. It fed the reduction into `cooldown_regen` as a `variable_bonus_max` (a `bonus`), but `cooldown_regen` is a `stacking_multiplier` stat (`buff_templates.lua:40`) — for which `_add_stat_buff` only accumulates the `.multiplier` field of non-first registrants and silently drops the `.bonus` (`buff_extension.lua:683-686`). Since the OE passive `bardin_engineer_passive_no_ability_regen` (multiplier -1) already creates `cooldown_regen`'s root `stat_buff[0]` at career init, the mirror's bonus was unconditionally dropped → zero effect. Caught by adversarial review (both verifiers, independently).

### Changed
- `career_tweaker_oe_cooldown.lua` — the managed buff template now uses `variable_multiplier_max = 1.0` (contributes a `multiplier`), so `variable_value = reduction` lands as `multiplier = reduction`, accumulating into the `cooldown_regen` root alongside the passive (-1) and pump (+0.4 × up to 5) — the channel `career_extension.lua:244-246` actually reads. Corrected the math comments + loc tooltip wording (bonus → multiplier).
- MOD_VERSION → 0.3.42-dev.

## 0.3.41-dev (2026-06-21) — Outcast Engineer: benefit from Cooldown Reduction gear (opt-in)

### Added (default OFF) — new toggle `oe_benefit_from_cooldown_reduction` (Armor & Overcharge group)
- **Outcast Engineer now benefits from Cooldown Reduction trinkets/charms.** Vanilla bug-by-design: the "Cooldown Reduction" property (`ability_cooldown_reduction`, weapon_properties.lua:186) grants the `activated_cooldown` stat (range −0.05..−0.10), but `activated_cooldown` is consumed ONLY inside `CareerExtension.start_activated_ability_cooldown` (career_extension.lua:424) behind an ability `cost` (career_extension.lua:418-420). The OE's Crank Gun ult `dr_4` (career_ability_settings_cog.lua:5-29: `cooldown = 60`, no `cost`) never hits that path — he recharges SOLELY through the `cooldown_regen` decay loop (career_extension.lua:241-246), driven by `bardin_engineer_pump_buff` (cooldown_regen +0.4 ×5, talent_settings_cog_dwarf_ranger.lua:20-22) vs `bardin_engineer_passive_no_ability_regen` (cooldown_regen −1, :7-9). So `activated_cooldown` and `cooldown_regen` are different stats → Cooldown Reduction gear did exactly nothing for him.
- **Fix:** when ON, mirror the OE's live `activated_cooldown` reduction onto an equal `cooldown_regen` bonus: `reduction = 1 - buff_extension:apply_buffs_to_value(1, "activated_cooldown")` (e.g. 0.90 → 0.10), maintained as a single managed `cooldown_regen` stat-buff worth that amount. A 10% Cooldown Reduction trinket → ~+0.10 cooldown_regen → his pump recharge ~10% faster, plus a small passive trickle offsetting the −1 passive.
- **Gating / safety:** OE-only (gated on local career == `dr_engineer`), owner-local (applies to `Managers.player:local_player().player_unit` only). Dynamic — re-evaluated on a throttled ~4×/sec tick from `mod.update` (NOT a new hook); keeps exactly ONE managed buff id, replacing (remove-then-add, `skip_net_sync`) on change so there's no drift / double-apply / accumulation. Toggle off, career switch, despawn, or no-CDR-gear (reduction below epsilon) all remove the managed bonus → exact vanilla. Buff is `client_side` (local recharge math, no RPC). The OE pump mechanic and base behavior are untouched (separate additive `cooldown_regen` bonus). Cleared eagerly in `on_disabled`.
- New module `career_tweaker_oe_cooldown.lua` (dofile'd like `career_tweaker_armor_overcharge.lua`); registers the `crt_oe_cdr_mirror` buff template (`variable_bonus_max = 1.0` so `variable_value` carries the live reduction). Loc keys + tooltip added; toggle nested in the existing "Armor & Overcharge (hook-based)" group, `[untested]`-prefixed per dev convention.

## 0.3.40-dev (2026-06-21) — Fix v0.3.39 cooldown-hook regression + tooltips/names/perk for the reworks

### Fixed (important)
- **`current_ability_cooldown` hook (v0.3.39) dropped its 2nd return value** — it returns `(cooldown, max_cooldown)` and the HUD cooldown bar consumes `max_cooldown`; my guard captured only the first (multi-return collapse), which would have nil'd the bar's denominator. Now pcall-wrapped capturing BOTH returns, fallback `(0, 1)`. Also covers the `career_extension.lua:698` nil (`max_cooldown` on a desynced swapped ability — same ability-swap crash class, user crash GUID 1efed1ef on v0.3.38).

### Added — talent tooltips/names + Abandon perk (the reworks now read correctly in-game)
- Talent **description overrides** (shared `_G.Localize` hook, gated per toggle) for: Natural Talent (#4), Numb to Pain (#5), Chain Reaction (#6), Fuel for the Fire (#7), Flame Unending (#3), and Mercenary Enhanced Training. Texts state the new mechanics.
- **Fixed a dead override key**: the prior Numb to Pain override was keyed `..._venting_2_desc`, but `UIUtils.get_talent_description` Localizes the talent's `description` FIELD (`..._venting_desc_2`) — so it never applied. Corrected.
- **Flame Unending name**: the lvl-25 slot now reads "Flame Unending" (overrides the talent's name key; it has no display_name field).
- **Abandon shown as a passive perk**: #3 appends an Abandon entry to `PassiveAbilitySettings.bw_3.perks` (name/desc via the Localize hook), so the now-innate Abandon is visible in the passive ability section. Reverted on toggle-off.

### Note
Passive Unstable Strength numbers (#1/#2) text left as-is — that's the shared career-passive description (also covers Blood Magic); rewriting it risks misstating the unchanged passive. The talent tooltips above are the player-facing surface for the reworks.

## 0.3.39-dev (2026-06-21) — Fix: ability-swap ult crash + career-unlock UI refresh

### Fixed (pre-existing features, surfaced by user testing — not the new reworks)
- **Ability-swap ult crash** (`Career Ability & Talent Swapping`). Live-swapping a career's `activated_ability` while the hero is spawned desyncs the spawned career extension's `_abilities`/cooldown state from `CareerSettings`, so the next ult had `CareerExtension:current_ability_cooldown(id)` return nil → engine crash at `career_extension.lua:424` (`apply_buffs_to_value(nil, "activated_cooldown")`). Repro: "swapped merc ult Slayer→none then ulted." Fix: guard the cooldown read so it never returns nil (treat the desynced ability as ready); the swap still applies cleanly on next spawn. Confirmed from crash log `console-2026-06-21-22.08.51`.
- **Career-select lock not refreshing** (`Character Experience Level` + `Unlock All Careers`). `HeroWindowCharacterSummary._setup_hero_selection_widgets` bakes each career's `content.locked` once at populate from the hero level (which both settings feed); changing those mid-menu left the tiles stale (careers wrongly locked/unlocked until toggling unlock-all forced a rebuild). Fix: track the live hero window and re-run its tile setup when a `level_override_*` / `unlock_all_careers` setting changes.

### Note
The 9 reworks from v0.3.35–.38 were NOT implicated in either crash (the crash log had zero rework-buff references and no auto-dump → the user wasn't on Unchained/Mercenary). They remain untested in-game — an Unchained + Mercenary run with a log still needed to confirm them.

## 0.3.38-dev (2026-06-21) — Remaining reworks: #4, #3, #7, #8 (Unchained) + Mercenary Enhanced Training

### Added (default OFF) — completes the Unchained set + the Mercenary rework
- **`rework_bw_unchained_natural_talent_ranged`** (#4) — Natural Talent → +6% ranged power per Unstable Strength stack (5% up to 6× with #1). New crt driver+stack buffs (`crt_sienna_natural_talent_ranged_*`), overcharge-chunk driven; replaces the vanilla −10% vent buff on `sienna_unchained_reduced_overcharge`.
- **`rework_bw_unchained_abandon_innate_flame_unending`** (#3) — Abandon (overcharge→cooldown, `sienna_unchained_health_to_ult`) appended to `PassiveAbilitySettings.bw_3.buffs` so it's **innate**; its lvl-25 slot becomes **Flame Unending** = −6% career-skill cooldown (`activated_cooldown`) per US stack (5% up to 6× with #1), via a new crt driver+stack.
- **`rework_bw_unchained_fuel_for_the_fire_vent`** (#7) — while the Fuel for the Fire talent is equipped, the career skill **clears only 25% overcharge** instead of all. Hook on `CareerAbilityBWUnchained._run_ability`: captures overcharge before the vanilla `reset()`, restores 75% after.
- **`rework_bw_unchained_career_skill_max_us`** (#8) — career skill grants the **max Unstable Strength melee bonus (+60%) for 10s** regardless of overcharge (new static buff `crt_unchained_ult_max_us`); same `_run_ability` hook.
- **`rework_es_mercenary_enhanced_training_tiered`** (Mercenary) — Enhanced Training: a melee hitting **2/3/4 targets grants 2/3/4 stacks of 5% attack speed for 6s** (10/15/20%); <2 = nothing. Custom `ProcFunctions.crt_enhanced_training_proc` (replicates vanilla except the ET branch; gate lowered to ≥2 only for that branch) + new `crt_merc_enhanced_training_as`; `markus_mercenary_passive.buff_func` patched to it.

### All 9 reworks now live (test all together)
#1 US rescale, #2 US→DoT, #3 Abandon-innate+Flame Unending, #4 Natural Talent→ranged, #5 Numb to Pain, #6 Chain Reaction ignite, #7 Fuel for the Fire vent, #8 career-skill max US, + Mercenary Enhanced Training. The per-US-stack reworks (#3/#4/#5) and the ability hooks (#7/#8) want in-game confirmation via the auto-dump/log.

## 0.3.37-dev (2026-06-21) — Unchained reworks #2 (US→DoT) + #6 (Chain Reaction ignite)

### Added (Unchained reworks group, default OFF)
- **`rework_bw_unchained_unstable_strength_dot`** (#2) — each Unstable Strength stack also grants **+12% burn DoT damage** (`increased_burn_dot_damage`; 10% up to 6× when #1 is on). Adds a 2nd stat_buff entry to the US stack buff so every overcharge-chunk stack carries it. Idempotent re-apply; restored on toggle-off.
- **`rework_bw_unchained_chain_reaction_ignite`** (#6) — Chain Reaction's on-burning-kill explosion (a zero-damage `slayer_leap_landing` push) now carries `dot_template_name = "burning_dot_3tick"`, so it **ignites nearby enemies**. Pure data patch on `ExplosionTemplates.sienna_unchained_burning_enemies_explosion`.

### Remaining (back-to-back next builds)
#3 Abandon→innate + Flame Unending, #4 Natural Talent→ranged power/US stack, #7 Fuel for the Fire vents 25% (ult hook), #8 career-skill max-US-stacks (ult hook), and Mercenary Enhanced Training/Paced Strikes (custom proc) — these need new crt buffs / hooks / a custom buff_func, built carefully so they don't crash.

## 0.3.36-dev (2026-06-21) — Unchained rework #5: Numb to Pain reworked (per Unstable Strength stack)

### Changed (replaces the prior Numb to Pain rework)
- **`rework_bw_unchained_numb_to_pain_4x_burn_kill_lose_on_hit`** (same toggle, new behavior) — Numb to Pain now grants, **per Unstable Strength stack: −6% damage taken AND −12% overcharge generated by Blood Magic** (`reduced_overcharge_from_passive`). When the Unstable Strength rescale (#1) is on, it mirrors US's 5oc/6× cadence at −5%/−10% up to 6×. Driven by the same `activate_server_buff_stacks_based_on_overcharge_chunks` engine function Unstable Strength uses, so stacks track current overcharge up and down (no on-hit removal). Reuses the pre-registered `crt_sienna_numb_to_pain_stack` (now two stat_buffs) + `crt_sienna_numb_to_pain_proc` (repurposed as the overcharge-chunk driver); `crt_sienna_numb_to_pain_remover` retired to an unused stub. The old "DR stack on burning elite/special kill, lose on hit" design is gone, per request.

### Notes
- Needs in-game confirmation that the driver's `update_func` runs while attached as a talent buff (Unstable Strength's identical driver runs as a career passive). The auto-dump will show the new `crt_sienna_numb_to_pain_*` wiring on next Unchained load.
- Next: Mercenary Enhanced Training / Paced Strikes; then Unchained #2/#3/#4/#6/#7/#8.

## 0.3.35-dev (2026-06-21) — Unchained rework #1: Unstable Strength rescale (master toggle)

### Added (Unchained reworks group, default OFF)
- **`rework_bw_unchained_unstable_strength_rescale`** — Unstable Strength now gives **+10% melee power per 5 overcharge, up to 6×** (vanilla 12% per 6, up to 5×). Patches the passive driver `sienna_unchained_passive_increased_melee_power_on_overcharge` (chunk_size 6→5, max_sub_buff_stacks →6) and the stack buff `sienna_unchained_passive_melee_power_on_overcharge` (max_stacks 5→6, multiplier 0.12→0.10), saving/restoring originals. This is the **master toggle** the remaining Unchained reworks read for their per-stack math (5%/6× when on, vanilla 6%/5× when off).

### In progress (built from the in-game auto-dump of bw_unchained + es_mercenary)
First of the requested Unchained set; the rest queued: US→DoT, Abandon→innate + new Flame Unending (CDR/stack), Natural Talent→ranged power/stack, Numb to Pain→DR + Blood-Magic overcharge/stack (replaces the existing NtP rework), Chain Reaction ignite, Fuel for the Fire vents 25% (gated on that talent), career-skill max-US-stacks; plus Mercenary Enhanced Training/Paced Strikes.

## 0.3.34-dev (2026-06-21) — Fix the auto-dump (it errored + never dumped in v0.3.33)

### Fixed
- v0.3.33's auto-dump spammed `player_manager.lua:559: Network backend has not been set` and never produced any `[crt:talent]` output. Two bugs: (1) `_crt_local_career` called `Managers.player:local_player()` **without** a pcall, and it was invoked from `on_game_state_changed` on **every** state including `StateSplashScreen`/`StateLoading`, where `local_player()` raises that engine error (only the inner lookups were guarded); (2) it relied on `player:career_name()`, which returns nil until the profile's `display_name` loads, so resolution came back nil even where it didn't throw.
- **Now:** `_crt_local_career` wraps the whole resolution in pcall (can't throw) and prefers the **career_system extension** on the spawned unit, with `career_name()` as a weaker fallback. The state trigger is gated to **`StateIngame` only**. Since the unit/career aren't ready at state-enter, a short **per-frame retry window** (`mod.update`, ~1×/sec for 20 s) fires the throw-proof, de-duped check until it dumps — so it lands once you're actually playing a reworked career, with or without opening the talent screen. De-dupe is set only on a **successful** dump. (Verified the failure in your `console-2026-06-21-20.10.30` log: crt v0.3.33-dev loaded, you were on bw_unchained + es_mercenary, talent screen opened 6×, but 8 errors and 0 dump lines.)

## 0.3.33-dev (2026-06-21) — Auto-dump talents for careers under active rework (bw_unchained, es_mercenary)

### Added (data harness — no gameplay effect)
- **Automatic talent/buff dump** for the careers currently being reworked (`bw_unchained`, `es_mercenary`). When the local player is on one of those careers, crt writes its full talent tree → buff map to the console log (`[crt:talent]` lines) automatically — once per career per session — so the exact internal names + proc values are captured from normal play without anyone running `/crt_dump_talents`. Fires from the talent-screen `on_enter` (guaranteed career-resolved) and each `on_game_state_changed` enter; de-duped per career/session. Pure read.
- Refactored the `/crt_dump_talents` body into reusable `mod.crt_dump_career_talents(career, reason)` (the command still works), and **widened the per-buff dump** to include `proc_chance / chunk_size / max_stacks / duration / event / buff_func / buff_to_add` so a tweak can be wired straight from the log.

### Why
Prepping the requested Unchained reworks (Unstable Strength rescale, US→DoT, Abandon→innate + new "Flame Unending", Natural Talent / Numb to Pain rescales, Chain Reaction ignite, Fuel-for-the-Fire vent %, career-skill max-stacks) and the Mercenary **Enhanced Training / Paced Strikes** rework (2 targets → 2×5% AS for 6 s, 3 → 15%, 4 → 20%, <2 → none). Those need the exact live talent→buff mapping; this dump produces it from a normal session.

## 0.3.32-dev (2026-06-20) — Armor & Overcharge toggles (4 hook-based, default OFF)

### Added
- **Four opt-in (default-OFF) Armor & Overcharge toggles** in a new `armor_overcharge_group`, served by a new feature file `career_tweaker_armor_overcharge.lua` (dofile'd from `career_tweaker.lua` the same way Tourney is). Pure runtime hooks gated live on `mod:get` — no `{apply,restore,active_count}` lifecycle and no `on_setting_changed` dispatch (VMF re-reads `mod:get` and deactivates the hooks when the mod is disabled). All four carry the `[untested]` prefix per dev label discipline.
  - `armor_gromril_ignore_chip` — Ironbreaker Gromril Armour AND Necromancer Cursed Armor (`sienna_necromancer_5_2_counter`) stacks are NOT consumed by chip / DoT / AOE sources (`dot_debuff` + the `DAMAGE_TYPES_AOE` set: globadier gas, warpfire, blightstorm, bile, ratling area). The armor still absorbs the next real hit.
  - `armor_specials_dont_break_gromril` — special enemies (Hookrat / Assassin / Leech, generic `Breeds[source].special` test) no longer consume Gromril Armour UNLESS the Ironbreaker has the Gromril Curse talent (`bardin_ironbreaker_max_gromril_delay`).
  - `unchained_no_overcharge_from_ff` — Sienna Unchained gains no overcharge from ally / friendly-fire damage (`side_by_unit` ally test).
  - `unchained_no_overcharge_from_disablers` — Unchained gains no overcharge from special-disabler grab/impact damage (mirrors the Tourney Balance mod).

### Architecture / correctness
- **Two hook targets, not one** (different functions, different authority — see the module header):
  - `DamageUtils.apply_buffs_to_damage` (ONE `mod:hook`) carries toggles #1-gromril / #2 / #3 / #4. **Host-authoritative** — gating the host's gromril consume means `rpc_remove_gromril_armour` is never sent, so clients never strip either (the client mirror strips unconditionally on RPC receipt). Overcharge likewise either applies locally or RPCs the owning client.
  - `PlayerUnitHealthExtension.add_damage` (ONE `mod:hook`) carries toggle #1-necromancer. **Per-victim own-peer** — the `sienna_necromancer_5_2_counter_remover` proc fires from `add_damage:702-703` on the victim's own peer.
- **Interception via per-instance method shim** restored in a pcall-protected finally: gromril hides the marker from `be:has_buff_type`; overcharge makes `be:apply_buffs_to_value` a no-op for stat `damage_taken_to_overcharge`; necromancer swallows the `on_damage_taken` event in `be:trigger_procs` for the one exempt tick.
- VMF no-duplicate-hook rule satisfied — both targets confirmed un-hooked elsewhere in crt. Added `/crt_regression_test` check `armor_overcharge_hook_targets_present`.
- **Caveat:** the Gromril and Overcharge toggles only take effect when the player running crt is the HOST (host decides whether to send the removal/conversion RPC). The Necromancer exemption is per-peer and works for the local Necromancer regardless of host.

## 0.3.31-dev (2026-06-20) — Big Rebalance fully on ice (localization keys commented out)

Completed freezing the Big Rebalance (Core's BR) integration. The BR **widgets** were already on ice (`career_tweaker_data.lua` 120-524 wrapped in `--[==[ … ]==]`) and the BR **module** is already stubbed/not-loaded (`career_tweaker.lua:127` dofile commented, no-op stub at 132) since bt was retired 2026-06-08. This release also comments out the now-orphaned BR **localization keys** (`cbr_*` group labels + ~160 toggle labels/tooltips + the BR passive-perks-rework descriptions, `career_tweaker_localization.lua` 238-641) in a matching `--[==[ … ]==]` block. Those keys were referenced only by the (commented) BR widgets and the (unloaded) BR module — no active feature uses them, verified by grep. The separate **Tourney Balance** (`trn_*`) feature is untouched and remains active. Net: the entire BR surface is now commented out / inert; nothing BR-related loads or appears in the menu. To restore, remove the three `--[==[`/`]==]` opener-closer pairs (data widgets, loc keys, and the module dofile).

## 0.3.30-dev (2026-06-18) — Actually fix Leading Shots text (mod loc keys don't reach global Localize) + docs

### Fixed
- **Leading Shots name + description still rendered wrong after v0.3.29 — real root cause found.** It was NOT the `{1}`→`%s` placeholder (that was a necessary but insufficient earlier fix). The talent UI resolves the title (`Localize(display_name or name)`, `hero_window_talents.lua:328`) and body (`get_talent_description` → `string.format`, `ui_utils.lua:69`) via the **global** `Localize`. **VMF does not register a mod's `_localization.lua` keys into the global `Localize`** (mod-loc scope), so `crt_engineer_leading_shots_name`/`_desc` never resolved — exactly the trap every *other* crt rework avoids by serving its text through the shared `_G.Localize` hook + `CRT_DESC_OVERRIDES` table. Added both keys to `CRT_DESC_OVERRIDES` (gated on `rework_dr_engineer_leading_shots`), hardcoding the count to skip `string.format` like the other entries. Title now reads **"Leading Shots"**, body **"Every 4 ranged attacks…"**.

### Added
- **`TALENT_TEXT_RENDERING.md`** — documents how VT2 renders a talent's name + description (title field precedence, printf-not-`{1}` placeholders, `%%` escaping, `description_values` shapes, and the mod-Localize scope trap with the `CRT_DESC_OVERRIDES` fix pattern), with engine file:line citations and a minimal recipe.

## 0.3.29-dev (2026-06-18) — Fix Leading Shots talent name + description text

### Fixed
- **Leading Shots talent showed the wrong name and description in-game.** Two bugs in the v0.3.27 rework:
  - **Name** — the talent title resolves as `Localize(talent.display_name or talent.name)` (`hero_window_talents.lua:328`). The rework set `description`/`icon` but never `display_name`, so the title kept localizing the vanilla `name` → "Ingenious Ordnance". Now sets `talent.display_name = "crt_engineer_leading_shots_name"` ("Leading Shots"), snapshotted + restored on disable.
  - **Description** — the body goes through `string.format(Localize(desc), values)` (`ui_utils.lua:format_localized_description`), which uses `%s`/`%d`, not `{1}`. The loc used `{1}`, so the count never substituted and a literal `{1}` rendered. Changed the placeholder to `%s` → now reads "Every 4 ranged attacks…".

## 0.3.28-dev (2026-06-18) — Zealot talent-dump command (diagnose Holy Fortitude) + regression-list sync

### Added
- **`/crt_dump_talents [career]`** (default `wh_zealot`) — logs a career's LIVE talent tree (post-rework) with each talent's internal name, display name, buffs, and each buff's `stat_buff`/`bonus`/`multiplier`. Needed because the local decompile is older than the current game: the Zealot "Holy Fortitude" talent doesn't exist in the decompile by that name, so `rework_wh_zealot_holy_fortitude_30_max_hp` targets a **best-guess** talent (`victor_zealot_passive_healing_received`) that the current game likely renamed/removed → `TalentIDLookup` returns nil → the rework silently no-ops (user reported it stuck at vanilla 180 HP). Run this, paste the `[crt:talent]` lines, and the rework gets re-pointed at the real talent.

### Fixed
- Synced `_CRT_BUFF_NAMES_EXPECTED` (the `/crt_regression_test` copy in `career_tweaker.lua`) with the canonical `_CRT_BUFF_NAMES` — the v0.3.27 Leading Shots add updated the canonical list but not the regression copy, which `/crt_regression_test` would have flagged. No functional impact (registration uses the canonical list).

## 0.3.27-dev (2026-06-18) — Restore the legacy "Leading Shots" Engineer talent (replaces Ingenious Ordnance)

### Added
- **Outcast Engineer: Leading Shots (replaces Ingenious Ordnance)** toggle in the Engineer rework group. Restores the pre-Patch-5.2.0 talent: **every 4th ranged shot is a guaranteed critical hit**, and crucially **it works with the Steam-Assisted Crank Gun** (which uses no ammo). Researched against Fatshark patch notes (added Patch 3.4 / Nov 2020, removed Patch 5.2.0 / Dec 2023 → replaced by Ingenious Ordnance) + the decompile.
  - **Crank Gun coverage:** the counter procs on `on_hit` filtered to ranged projectile attack types (`projectile` / `instant_projectile` / `heavy_instant_projectile`), **not** `on_ammo_used` — the ammo-less Crank Gun never fires `on_ammo_used`, but its bullets are ranged projectiles that trigger `on_hit`, so they count.
  - **Implementation:** a 3-buff chain using only **stock** buff funcs — counter (`add_buff_on_first_target_hit`, ranged-only) → accumulator (`max_stacks 4`, `reset_on_max_stacks`, `add_remove_buffs`) → guaranteed-crit buff (`buff_perks.guaranteed_crit`, consumed on the next `on_critical_action`). Modeled on Mercenary Paced Strikes + the engineer's own Scavenged-Shot accumulator. Swaps `Talents.bardin_engineer_improved_explosives` (slot [2,1]) `buffs`/`icon`/`description` with snapshot/restore, per the existing `rework_*` framework. Three names added to `_CRT_BUFF_NAMES` (alphabetical; NetworkLookup-deterministic — version-lockstep).
  - **Icon:** reuses `bardin_engineer_ranged_crit_count` — the orphaned talent icon already in the shipped `gui_icons` atlas (referenced by no current talent = the original Leading Shots art). No asset shipped.
  - **Scope (additive):** guaranteed crit every 4th ranged shot; the other 3 keep their normal random crit chance (the original's full random-crit suppression needs a crit-resolver hook — not done). While ON, the Ingenious Ordnance reworks have no effect (the talent is swapped out) — they don't conflict/crash.
  - **To verify in-game:** toggle on, fire 4 ranged shots, confirm the 4th crits + the icon renders; confirm the Crank Gun also crits on its cadence. (WIP — the in-game talent tooltip text may show a raw loc key if crt's loc isn't registered into the game's `Localize`; the *mechanic* is independent of that.)

## 0.3.25-dev (2026-06-17) — Tourney Balance Testing port: Phase 1 (career talent toggles)

### Why
Port the "Tourney Balance Testing" Workshop mod's career/talent changes into crt as opt-in, default-OFF toggles. Phase 1 = the clean per-career data mutations (BuffTemplate field patches with vanilla snapshot/restore); hook-based / talent-row-rework / ability-body changes are deferred to a later phase.

### Changed
- New `career_tweaker_tourney.lua` — a 3rd `{apply, restore, active_count}` module loaded alongside `balance` + `big_rebalance`, with **17 default-OFF `trn_*` toggles** (one per career across all 5 characters). Each faithfully transcribes that career's Tourney values, verified against the vanilla decompile, and applies via the same snapshot/restore engine as `career_tweaker_balance.lua`.
  - Two brand-new BuffTemplates (`victor_bountyhunter_blessed_melee_attack_speed_buff`, `victor_priest_5_2_speed_buff`) are registered **unconditionally as stubs** at load (alphabetical) per the NetworkLookup-determinism rule, with bodies installed by `custom_apply`.
  - **Conflict guard:** 4 toggles overlap existing crt reworks on the same buff field (`trn_es_huntsman`, `trn_wh_bountyhunter`, `trn_wh_zealot`, `trn_bw_adept`). A `_CONFLICTS` map makes the Tourney entry skip entirely while its matching `rework_` toggle is on, so they can't corrupt each other's vanilla snapshot. Documented in the tooltips.
- `career_tweaker.lua` — load the tourney module + call `tourney.apply()` in `on_game_state_changed` / `on_setting_changed` (`^trn_` and `^rework_` branches) and `tourney.restore()` in `on_disabled`.
- `_data.lua` / `_localization.lua` — new "Tourney Balance (Careers)" VMF group with per-character sub-groups (17 checkboxes + tooltips).

### Deferred (later phase)
Hook-based / talent-row / ability-body Tourney career changes (custom proc functions, core-combat damage math, ActivatedAbilitySettings/PassiveAbilitySettings restructures, ability re-impls) — captured per-career in the generation notes.

### To verify (in-game)
Enable a `trn_*` toggle (e.g. Tourney: Foot Knight), load a mission, confirm the tuned values; `/crt_regression_test`; disable and confirm vanilla restores. (Local/friends test build; not on Workshop.)

## 0.3.24-dev (2026-06-17) — Waystalker: Serrated Shots on all arrow types (toggle)

### Why
Requested: make Waystalker's Serrated Shots (bleed on critical ranged hits) work regardless of arrow type. Vanilla gates the bleed in `damage_utils.lua:3698`:
`has_perk("kerillian_critical_bleed_dot") and damage_profile.charge_value == "projectile" and not has_perk("kerillian_critical_bleed_dot_disable")`.
Every Kerillian arrow damage profile already uses `charge_value="projectile"` (arrow_carbine / arrow_sniper / *_shortbow / *_trueflight, verified in `damage_profile_templates.lua`), so the only thing that disables the bleed by arrow type is the `kerillian_critical_bleed_dot_disable` perk — granted by Hagbane (`shortbows_hagbane.lua:301-303` `server_buffs`) and the Chaos Wastes `we_deus_01` bow, both via the buff `we_deus_01_kerillian_critical_bleed_dot_disable` (`morris_buff_settings.lua:6332`), whose ONLY effect is that perk.

### Added
- New toggle `rework_we_waywatcher_serrated_shots_all_arrows` (Bot/Career reworks → Kerillian → Waystalker; default OFF). A single BALANCE_MODS patch clears the `perks` list of `we_deus_01_kerillian_critical_bleed_dot_disable`, neutralizing the disable so Serrated Shots crits also bleed on Hagbane / we_deus_01. Uses the existing apply/restore engine (one-time data mutation; no per-frame cost; fully reversible on toggle-off). Takes effect on the next weapon equip / mission load.

## 0.3.23-dev (2026-06-16) — Crash fix: Zealot Castigate rework set max_stacks on the wrong buff

### Why
Crash report: `buff_function_templates.lua: bad argument #2 to 'min' (number expected, got nil)`.
Traced to `rework_wh_zealot_castigate_4pct_as_per_fiery_faith`. The rework switches
`victor_zealot_attack_speed_on_health_percent`'s `update_func` to
`activate_buff_stacks_based_on_health_chunks`, but that engine func reads `chunk_size`,
`buff_to_add`, **and `max_stacks`** all from `buff.template` — i.e. the **parent** buff that
carries `update_func`, not the child `_buff` (verified `buff_function_templates.lua:2591-2596`).
The rework set `chunk_size` on the parent but `max_stacks` on the child. The vanilla parent
used the *threshold* func and has no `max_stacks` field, so `template.max_stacks` was `nil`
at `math.min(floor(uncursed_max_health / chunk_size) - 1, template.max_stacks)` → crash.

### Changed
- `career_tweaker_balance.lua` (`rework_wh_zealot_castigate_*`) — added
  `{ buff = "victor_zealot_attack_speed_on_health_percent", field = "max_stacks", value = 5 }`
  on the **parent** buff (the chunk gate). Mirrors the canonical
  `victor_zealot_passive_move_speed` shape: parent carries `buff_to_add` + `chunk_size` +
  `max_stacks` + `update_func` together. Child `_buff` `max_stacks`/`multiplier` patches kept.
- `career_tweaker_balance.lua` (`rework_wh_zealot_fiery_faith_*`) — same wrong-target class,
  no crash (vanilla parent already has `max_stacks=6`) but the documented "30 stacks / +30%
  cap" was silently gated to 6 (+6%) because the parent's `max_stacks` was never widened.
  Added `{ buff = "victor_zealot_passive_increased_damage", field = "max_stacks", value = 30 }`.

### To verify
- In a run as Zealot (Victor) with the Castigate talent (`victor_zealot_attack_speed_on_health_percent`)
  and Career Tweaker enabled: take damage and confirm no crash; attack speed should ramp one
  stack per 30 HP missing up to 5 stacks (+20% at 150 HP missing).
- With Fiery Faith (`victor_zealot_passive_increased_damage`): power should now ramp to +30%
  at 150 HP missing (30 chunks × 1%), not cap early at +6%.

## 0.3.22-dev (2026-06-07) — on_disabled now unwinds talent swaps + documents the rest

### Why
Audit 2026-06-07 finding F13 (BUG_CLASSES §7 — togglable-mod limitation): `mod.on_disabled` restored only the balance / big_rebalance buff-template mutations and left the **talent swaps** (TalentTrees / CareerSettings activated_ability + passive_ability rebinds) and the global table/hook mutations behind. Toggling the mod off mid-session left swapped careers swapped until a restart. Per the repo's accepted class-7 pattern (gt v0.2.56, Issue #15): restore what's cheap, document the rest.

### Changed
- `career_tweaker.lua:229-247` — factored the talent-swap restore loop out of `apply_talent_swaps` into a reusable file-scope `restore_talent_swaps()` (rebind saved originals + clear `_talent_swap_originals`; no-op when empty). `apply_talent_swaps` now calls it instead of inlining the loop — behavior unchanged.
- `career_tweaker.lua:446-475` (`on_disabled`) — now calls `restore_talent_swaps()` (cheap unwind) + `refresh_talent_ui()` so an open talent picker visibly reverts, then `mod:echo`s a one-line restart-required note for the genuinely non-reversible mutations: the unconditional `crt_*` stub registrations in `BuffTemplates` + `NetworkLookup.buff_templates` (removing them would shift later NetworkLookup indices and break cross-peer `rpc_add_buff` determinism) and the VMF-installed hooks (VMF deactivates them on disable and each body already gates on `mod:get`, so they no-op, but the wrappers persist until restart).

### Tests
- `career_tweaker.lua` — added `_rt_register("on_disabled_unwinds_talent_swaps", ...)`. Behavioral: seeds a synthetic pending-swap whose career_name is absent from `CareerSettings` (so the restore iterates it without writing any real game table), calls `restore_talent_swaps()`, and asserts `_talent_swap_originals` is cleared. Restores the live table afterward. FAILS if the F13 unwind path is removed or the helper goes missing.

### To verify
- In-keep: enable a talent swap (e.g. set a career's `talent_swap_*` dropdown), confirm the swap applied, then toggle Career Tweaker OFF in the VMF menu. The swapped career should revert to its vanilla tree/ability (open the talent picker to confirm), and chat should show the `[crt] Talent swaps + balance reworks reverted…` restart note once.
- `/crt_regression_test` — the new `on_disabled_unwinds_talent_swaps` check passes alongside the existing suite.

## v0.3.21-dev (2026-06-06) -- Add "Unlock all careers" toggle (owned-DLC only)

Sibling feature to the level override: a single checkbox that bypasses the level requirement for every career the player OWNS. DLC ownership is preserved — unowned-DLC careers (Grail Knight, Sister of the Thorn, Warrior Priest, Outcast Engineer, Necromancer) stay locked unless the player actually owns the DLC. Matches CLAUDE.md § DLC Ownership Gate: "modded mods unlock vanilla progression, NOT paid DLC content."

**Implementation** (verified against decompiled source): the vanilla unlock chain is `local_is_unlocked_function` (career_settings.lua:23) -> `override_available_for_mechanism` -> `is_dlc_unlocked` (DLC GATE) -> `ProgressionUnlocks.is_unlocked_for_profile(display_name, hero_name, hero_level)` (LEVEL GATE). DLC careers (lake/bless/cog/shovel/woods) have bespoke `is_unlocked_function`s that short-circuit after the DLC check without calling the level gate — so for DLC careers, ownership IS the whole gate; this toggle correctly has no effect on them. Hooking just `ProgressionUnlocks.is_unlocked_for_profile` is therefore the single, surgical fix: it bypasses the level check only and runs DOWNSTREAM of the DLC gate, which has already locked unowned DLC careers. Vanilla already had a built-in dev flag for this exact behavior at `progression_unlocks.lua:206` (`Development.parameter("unlock_all_careers")`); this toggle gives it a user-facing surface.

**Scope:** Local character-select only. Off by default. No XP / unlock state ever writes to the backend.

## v0.3.20-dev (2026-06-06) -- Fix: level override didn't unlock talents / level-gated features

User report: setting a character's level higher (Character Experience Level Override) showed the higher level but still wouldn't let you **equip talents** or unlock the things you get from leveling.

**Root cause** (verified against decompiled source): the existing override is a single hook on `ExperienceSettings.get_experience`, which only covers DISPLAY reads. The functional gates read raw experience DIRECTLY from the backend mirror — `BackendInterfaceTalentsPlayfab._validate_talents` (backend_interface_talents_playfab.lua:234) does `self._backend_mirror:get_read_only_data(profile_name.."_experience")` → `ExperienceSettings.get_level(...)` → strips any talent whose `ProgressionUnlocks.is_unlocked("talent_point_"..i, hero_level)` is false (`career_talents[i] = 0`). That path never touched the display hook, so the gate saw the real (low) level and stripped the talents.

**Fix:** override the mirror's `<hero>_experience` read too, so the functional gates see the override level. Class()-copy caveat handled: the live mirror is `PlayFabMirrorAdventure` (copies methods from `PlayFabMirrorBase` at load time per VT2's class system), so hooking only the base would never fire — the hook targets every concrete mirror class (`PlayFabMirrorAdventure` / `PlayFabMirrorDedicated` / `PlayFabMirrorBase`). Read-only (returns a value, never writes); type-matched to vanilla's stored string. No XP is persisted.

## 0.3.19-dev (2026-05-30) -- Loc integrity: add missing passive-perks-rework descriptions

### Why
`qa/check_name_integrity.ps1` check #2 flagged 9 `description = "<key>"` assignments in `career_tweaker_big_rebalance.lua` that resolved in no loc table (mod/any-mod/vanilla): `kerillian_maidenguard_perk_{1,2,3}_desc`, `victor_zealot_perk_{1,2,3}_desc`, `victor_bountyhunter_perk_{1,2,3}_desc`. These are the `perks` UI sub-entry descriptions written into `PassiveAbilitySettings.we_2 / wh_1 / wh_2` by the three `cbr_*_passive_perks_rework` BR toggles. Investigation: the vanilla perk-description convention is `career_passive_desc_<id><letter>_<n>` (e.g. `career_passive_desc_we_2b_2`), NOT these keys — and they appear nowhere in the decompiled source NOR the Big Rebalance extract (`_big_rebalance_extract` ships `career_perk_1/2/3` icon atlas names but no `*_perk_*_desc` strings). So these are crt's own invented keys that were never added to crt's loc table — without entries the hero UI would render the raw key strings on those reworked passives.

### Changed
- `career_tweaker_localization.lua` — added the 9 perk-description loc entries. English is grounded in the documented vanilla passive `buffs` lists (`career_ability_settings.lua` we_2 / wh_1 / wh_2 — dodge/stamina-aura/ress for Handmaiden, low-health-power/uninterruptible/invuln for Zealot, periodic-crit/reload/ammo for Bounty Hunter); no invented numbers.

### Notes
- Resolves all 9 career_tweaker entries in the 13 check_name_integrity errors. CONFIRMED crt's-own keys, not vanilla — no validator allowlist needed.

## 0.3.18-dev (2026-05-25) -- Restore dev/alpha/beta load banner (PROJECT_STANDARDS § 3.6 update)

### Why
User feedback 2026-05-25 EOD: earlier today's chat-spam cleanup pulled the `mod:echo("<Name> v" .. MOD_VERSION)` startup line from every mod. That's correct for stable (>=1.0.0) builds but hides the active version for in-flight dev/alpha/beta work -- the user can't tell at a glance which patch is running. PROJECT_STANDARDS § 3.6 amended: dev/alpha/beta/0.x versions MUST echo `[<mod_id>] v<version> loaded` at module load; stable versions stay silent.

### Changed
- `career_tweaker.lua` -- added a track-detector `if` after the applied-marker line: matches `-dev$` / `-alpha$` / `-beta$` / `-rc%d*$` / `^0%.`. When any branch fires, `mod:echo("[crt] v<MOD_VERSION> loaded")` runs once.

## 0.3.17-dev (2026-05-25) -- Remove startup banner echo + tidy on_setting_changed (chat-echo policy: PROJECT_STANDARDS § 3.6)

### Why
User feedback 2026-05-25: `"on enabling debug logging, I'm getting needless echos to the chat that it's enabled"` and `"on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV"`. Audit found 13 mods with redundant `mod:echo("<Name> v" .. MOD_VERSION)` lines at module load and one mod with `mod:echo("Setting changed: " .. setting_id)` in on_setting_changed (career_tweaker -- the source of the Debug Logging chat echo).

Policy decision codified in PROJECT_STANDARDS.md § 3.6 "Chat-echo policy":
- **NEVER** at module load -- the applied marker `[crt] enabled v<X> settings_fp=<hash>` line is the canonical version surface, lives in the log, never spams chat.
- **NEVER** in on_setting_changed for routine settings -- use `_dbg` (gated on enable_debug_logging) if a diagnostic trace is needed.
- **OK** in on_setting_changed only for explicit high-impact toggles (bt master toggle, gt AI toggle).
- **OK** in user-typed chat command bodies (`/<feature>_regression_test`, `/verify_*`, etc.).

### Changed
- career_tweaker.lua -- removed the load-time `mod:echo("career_tweaker v" .. MOD_VERSION)` banner. The applied marker line (`mod:info("[crt] enabled v%s settings_fp=%s", ...)`) further down already surfaces the version + settings hash in the log. `mod:info("career_tweaker v%s loaded", MOD_VERSION)` retained for log-side visibility.
- career_tweaker.lua:329 -- removed `mod:echo("Setting changed: " .. tostring(setting_id))` from on_setting_changed. The echo fired in chat on EVERY widget flip (including Debug Logging itself), which was the source of the user-reported "needless echos when enabling debug logging". Diagnostic trace now routes through `_dbg("on_setting_changed: %s", ...)` -- file only, gated on enable_debug_logging.
- itemV2.cfg -- updated the description's "Mention the mod version" bug-report instruction. Previous text told users to find the version "at the top of the in-game chat when you load into the keep" -- now points them at the console log (search for the `enabled v` line) or `/<mod>_regression_test`.

### Build
VMBLauncher.exe build career_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.3.16-dev (2026-05-25) -- Fix unescaped %APPDATA% in Debug Logging tooltip + add localization_format_safe runtime test

### Why
User report: "invalid string format on mouseover for Debug Logging" -- the canonical Universal Debug Logging tooltip (PROJECT_STANDARDS.md S 3.6) shipped with a literal %APPDATA%. Lua's string.format reads %A as a format directive and raises invalid option '%A' to 'format', surfacing as a red error tooltip in the VMF settings UI. All 16 active mods were affected (every mod ships the same canonical tooltip text).

### Changed
- career_tweaker_localization.lua -- escaped literal % in enable_debug_logging_tooltip so VMF's tooltip render path sees %%APPDATA%% (renders as %APPDATA% to the player). Same wording, just escaped.
- career_tweaker.lua -- added _rt_register("localization_format_safe", ...) runtime check. dofiles the loc table and pcall(string.format, value) on every entry; surfaces any unescaped % via /<mod_id>_regression_test. Catches the bug class even when the static check (qa/check_localization.ps1) is skipped.

### Notes
Repo-wide multi-layer defense landing across all 16 mods in this sweep:

1. Layer 1 -- 16 mods' loc strings fixed.
2. Layer 2 -- qa/check_localization.ps1 extended to parse loc.<key> = { en = "..." } assignment style (chaos_wastes_tweaker's pattern -- previously slipped detection).
3. Layer 3 -- _rt_register("localization_format_safe", ...) runtime check in every mod.
4. Layer 4 -- tools/vmb-launcher/CLAUDE.md doctrine update: "Run qa/check_localization.ps1 before declaring any localization edit complete."
5. Layer 5 -- documentation: LOCALIZATION_STANDARD.md S 1 "Recurring offender" worked example, docs/BUG_CLASSES.md S 16 new entry, PROJECT_STANDARDS.md S 3.6 canonical tooltip text now uses %%APPDATA%%.

Static check (qa/check_localization.ps1) reports 0 errors post-fix (down from 15 detected + 1 hidden in chaos_wastes_tweaker).

### Build
VMBLauncher.exe build career_tweaker -- verification only. NOT deployed, NOT uploaded.

## 0.3.15-dev (2026-05-25) — Applied marker (universal — PROJECT_STANDARDS.md § 3.6)

### Why
Every mod now prints a single `mod:info("[crt] enabled v<X.Y.Z> settings_fp=<8-hex>")` line at load. Walks the data widget tree, FNV-1a-32 hashes setting=value pairs. Self-documenting console_logs: scrolling back you can see which build + config was running. ALWAYS fires (not gated on debug_logging — operational telemetry).

### Changed
- `career_tweaker.lua` — added file-local `_settings_fingerprint()` helper + `mod:info("[crt] enabled ...")` applied-marker line right after the `_dbg_alert` helper.
- `itemV2.cfg` — bumped to v0.3.15-dev.

## 0.3.14-dev (2026-05-25) — Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6)

### Why
User-requested two-channel debug discipline: `_dbg` for confirmation / dump / expected behavior (log file only), `_dbg_alert` for unexpected / wrong / mismatch (log file + in-game chat). Helpers installed in every active mod.

### Changed
- `career_tweaker.lua` — installed `_dbg_alert` helper alongside existing `_dbg`. Added `_rt_register("dbg_helpers_two_channel", ...)` alongside the existing four crt regression checks.
- `itemV2.cfg` — bumped to v0.3.14-dev.

### Notes
- 0 existing `_dbg(...)` call sites in this mod (helper was previously unused).
- 0 bare `mod:echo` reclassified — all `mod:echo` calls are inside chat command bodies or are permanent operational output.

## 0.3.13-dev (2026-05-25) — Tighten localization strings to vanilla style (~20 entries rewritten)

### Why

Mod-menu tooltips for the 5 character-XP-level overrides and the rework_* talent descriptions read as multi-paragraph essays. Vanilla VT2 talent text is dry single-sentence mechanical detail with magnitudes inline. This pass aligns crt with the vanilla voice per the new `LOCALIZATION_STANDARD.md` § 11 rules.

### Changed

- `level_override_<char>_tooltip` × 5 (Bardin / Kruber / Kerillian / Saltzpyre / Sienna): collapsed identical 240-char tooltips down to "Force X's reported XP level (shared across all 4 careers). 0 = real XP; 1-35 = override. Modded realm only; never writes to the backend."
- `cbr_group_description`: dropped the "subscribe to it separately, then restart the game" prose; kept the bt-master-required gate.
- `rework_general_stagger_thp_description`, `rework_general_thp_kill_minimum_description`, `rework_general_enhanced_power_10pct_description`, `rework_general_mainstay_stagger_15pct_description`: trimmed implementation-details paragraphs, kept magnitudes inline (0.375/1.5/3 THP, +7.5%% → +10%%, etc.).
- BR talent reworks: `rework_es_huntsman_prowl_monster_power_description`, `rework_es_mercenary_hellborgs_tutelage_description`, `rework_es_knight_valiant_charge_*_description`, `rework_es_questingknight_virtue_of_ideal_*_description`, `rework_dr_ranger_exuberance_stacking_dr_description`, `rework_bw_unchained_wildfire_burst_and_radius_description`, `rework_bw_unchained_numb_to_pain_*_description`, `rework_wh_zealot_smite_random_crits_description`, `rework_wh_zealot_ability_green_to_thp_description`, `rework_wh_zealot_castigate_*_description`, `rework_wh_bountyhunter_blessed_combat_*_description`, `rework_wh_bountyhunter_salvaged_ammo_*_description`, `rework_wh_priest_shield_of_faith_*_description`: dropped vanilla-comparison preambles, kept the magnitudes.

### Not touched

- Bounty Hunter mutex-cluster tooltips (`rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr_tooltip` / `cbr_bh_passive_perks_rework_tooltip`) — the leading "choice (A/B) of (B). Alternative to '(B/A) X' — these are mutually exclusive..." is load-bearing per LOCALIZATION_STANDARD.md § 10. Cannot tighten the prefix.
- Talent rework descriptions that already match vanilla style.

### Build

VMBLauncher.exe build career_tweaker — verification only.

## 0.3.12-dev (2026-05-25) — Standardize Debug Logging toggle (universal convention)

### Why
Repo-wide convention: every mod now exposes a single `enable_debug_logging` checkbox at the bottom of its VMF widget tree (PROJECT_STANDARDS.md § 3.6). crt previously had no debug toggle at all — added.

### Changed
- `career_tweaker_data.lua` — new top-level `enable_debug_logging` checkbox (default `false`) at the bottom of `options.widgets`, NOT nested in any group.
- `career_tweaker_localization.lua` — added `enable_debug_logging` + `enable_debug_logging_tooltip` strings.
- `career_tweaker.lua` — added file-local `_dbg(fmt, ...)` helper gated on `mod:get("enable_debug_logging")`. Output prefixed `[crt:dbg]`.
- `itemV2.cfg` — title + description bumped to v0.3.12-dev.

### Notes
- No existing debug key to rename (crt had none).

## 0.3.10-dev (2026-05-24) — §15 belt-and-suspenders runtime test for v0.3.9 rawget conversion

### Why
Audit `.test_coverage_audit_2026-05-24.md` PARTIAL row 3: the v0.3.9 `NetworkLookup.buff_templates` rawget conversion (`career_tweaker_big_rebalance.lua:124`) was lint-covered (regression-lint.ps1 `strict-table-lookup`) but lacked a target-specific runtime check (the pre-existing `rawget_on_buff_templates_marker` is generic). Per the §15 doctrine update appended this round, lint-covered fixes ALSO require a runtime regression test.

### Added
- Source-pattern marker constant `CT_CRT_BIG_REBALANCE_RAWGET_MARKER_v0_3_10 = "crt-big-rebalance-rawget-hardened"` near the top of `career_tweaker.lua`.
- `_rt_register("crt_big_rebalance_uses_rawget", ...)` at the bottom of `career_tweaker.lua`. Two assertions:
  1. The marker constant retains its expected value.
  2. `rawget(NetworkLookup.buff_templates, <known-bad-key>)` returns `nil` without raising.

### Verification
1. Restart VT2 with the mod enabled, load the keep.
2. Run `/crt_regression_test` in chat. Expect `PASS: crt_big_rebalance_uses_rawget` alongside the pre-existing checks.

## 0.3.9-dev (2026-05-23) — Convert 1 NetworkLookup lookup to rawget (latent strict-__index crash fix)

### Why
`NetworkLookup.*` subtables install a strict `__index = error()` metatable at boot. Plain `NetworkLookup.foo[key]` on a missing key throws — see memory `reference_vt2_strict_lookup_rawget.md`. The lint pass on 2026-05-23 flagged the talent-buff registration site as latent: the BR-stub registration path queries `NetworkLookup.buff_templates[name]` to skip already-registered names, but the strict metatable means an unregistered name would crash *before* the registration write that would fix it.

### Changed
- `career_tweaker_big_rebalance.lua` (`_register_talent_buff_template_if_missing`) — converted `not NetworkLookup.buff_templates[name]` to `not rawget(NetworkLookup.buff_templates, name)` so the "is this name new?" check returns false (write the entry) instead of crashing on the strict lookup.

### Verification
1. `tools/mod-lint/lint-mod.ps1` — passes.
2. `tools/lint/regression-lint.ps1 -Quiet` — site no longer appears in `strict-table-lookup` findings.

## 0.3.8-dev (2026-05-23) — Namespace `regression_test` chat command to avoid cross-mod collision

### Why
Seven mods registered `mod:command("regression_test", ...)`. VT2 chat commands are global — only the first mod wins, the rest fail silently with `[ERROR] (command): command name 'regression_test' is already used by another mod 'cim'`. Detected in PC-A log 2026-05-23 20:50:52.

### Changed
- `career_tweaker.lua` — renamed `regression_test` → `crt_regression_test`. Verification log line added at registration site.

### Verification
1. Restart VT2. No `[ERROR] (command):` line in console_logs about this command name.
2. Run `/crt_regression_test` in chat. Command fires and prints results.
3. Per memory `feedback_vt2_verify_before_shipping.md`.

## 0.2.22-dev (2026-05-19)

### Added: Ranger Veteran +25 base HP (toggle)

New rework under **Rework: Bardin > Rework: Ranger Veteran**:
`rework_dr_ranger_base_hp_plus_25` — adds 25 to Ranger Veteran's base max HP (vanilla 100 → 125, matching Witch Hunter Captain).

Implementation: patches `CareerSettings.dr_ranger.attributes.max_hp` in `custom_apply` and restores the original in `custom_restore`. `PlayerUnitHealthExtension._get_base_max_health` reads `SPProfiles[profile].careers[index].attributes.max_hp`, and `SPProfiles.dwarf_ranger.careers` holds direct references to `CareerSettings.dr_*` (sp_profiles.lua:163), so the single field patch is what every health-calc path consumes. Takes effect on next mission load / hero respawn (vanilla recalculates max at extension init); does not retroactively bump an already-spawned Ranger's max in the current mission. Stacks multiplicatively with `max_health` / `max_health_alive` buffs.

## 0.2.21-dev (2026-05-19)

### Added: Zealot ability converts green → temporary HP (toggle)

New rework under **Rework: Saltzpyre > Rework: Zealot**:
`rework_wh_zealot_ability_green_to_thp` — when on, every Zealot Holy Fervour activation moves all current permanent (green) HP into temporary (white) HP. Synergizes with Zealot's missing-health damage passive: a full-HP activation drops him to 0 permanent HP, maxing the passive's damage multiplier while the THP buffer keeps him alive (and decays normally). Existing THP is preserved; conversion fires once per activation.

Implementation: `mod:hook_safe("CareerAbilityWHZealot", "_run_ability", ...)` reads `current_permanent_health()` and calls `health_extension:convert_to_temp(permanent)`. `convert_to_temp` self-routes — server mutates GameSession fields directly; client fires `rpc_request_convert_temp` to the server. Server-side clamps via `math.min(current_health, amount)`, so the read-back amount is overflow-safe. No `BuffTemplates` mutation and no `NetworkLookup.buff_templates` registration, so the toggle is host-controlled with no peer drift (per `feedback_vt2_gated_registration_diverges.md`).

## 0.2.20-dev (2026-05-18)

### Fixed: HARD DLC paywall bypass via talent swaps

`apply_talent_swaps` iterated all 20 careers — including the five DLC careers (Grail Knight, Warrior Priest, Necromancer, Outcast Engineer, Sister of the Thorn) — and copied their talent trees + `activated_ability` + `passive_ability` onto the player's selected career without consulting DLC ownership. The dropdown UI listed every career unconditionally, so a player who didn't own a DLC could pick its career as a swap source and the talents/ability took effect **at runtime**: Grail Knight ult, Warrior Priest aftershock heal, Necromancer commander, Outcast Engineer pressure gauge, Sister of the Thorn entanglement. That is a paid-content runtime bypass, not just a UI peek — fixed.

#### The gate

New helper `_career_requires_unowned_dlc(career_name)` mirrors `_skin_requires_unowned_dlc` from `cosmetics_tweaker.lua:38`, but reads `CareerSettings[career_name].required_dlc` instead of `ItemMasterList[skin_key].required_dlc`. Base careers have no `required_dlc` field so they short-circuit to false; DLC careers carry the field via their per-DLC `career_settings_<dlc>.lua` registration in the VT2 source.

DLC IDs settled (cited from the decompiled `c:\Users\danjo\source\repos\Vermintide-2-Source-Code` per-DLC `career_settings_*.lua` files):

| Career | `required_dlc` | Source file |
|---|---|---|
| `dr_engineer` (Outcast Engineer) | `"cog"` | `scripts/settings/dlcs/cog/career_settings_cog.lua:32` |
| `es_questingknight` (Grail Knight) | `"lake"` | `scripts/settings/dlcs/lake/career_settings_lake.lua:21` |
| `wh_priest` (Warrior Priest) | `"bless"` | `scripts/settings/dlcs/bless/career_settings_bless.lua:22` |
| `bw_necromancer` (Necromancer) | `"shovel"` | `scripts/settings/dlcs/shovel/career_settings_shovel.lua:21` |
| `we_thornsister` (Sister of the Thorn) | `"woods"` | `scripts/settings/dlcs/woods/career_settings_woods.lua:21` |

(The task brief listed only four DLC careers; the data-driven gate auto-covers `we_thornsister` too — base careers in `scripts/settings/profiles/career_settings.lua` have zero `required_dlc` entries, so no false positives.)

#### Apply-time, both sides

The gate runs at swap-apply time inside `apply_talent_swaps`, not at dropdown-build time:

1. **Source check (load-bearing)** — if `_career_requires_unowned_dlc(src_name)` is true we `goto continue` and never mutate the destination career's slot. This is what closes the bypass.
2. **Target check (defensive)** — same skip if `_career_requires_unowned_dlc(career_name)` is true. A non-owner can't equip the DLC career anyway, but if they hand-edit settings we still refuse to mutate that career's `TalentTrees` slot / `activated_ability` / `passive_ability`.

Both skips log an info-level line; nothing visible to the player.

#### Why the UI isn't touched

VMF dropdown options are part of the widget's saved schema. Dropping options at registration time would invalidate any user's existing setting that referenced a now-removed option (the saved value falls through to default; if they re-acquire the DLC the option doesn't come back without a restart). The apply-time gate is data-driven, so it works whether the player owns the DLC at boot, mid-session, or never — and saved settings stay portable across machines with different DLC ownership.

#### Balance reworks unchanged

`career_tweaker_balance.lua` was re-audited: `BALANCE_MODS` patches `BuffTemplates` entries for `victor_zealot_power`, `bardin_ranger_attack_speed`, `kerillian_maidenguard_crit_chance`, `victor_bountyhunter_activated_ability_railgun_delayed_add`, `markus_mercenary_crit_count`, `wh_captain` parry actions, `thp_tank`, and `Breeds[*].bloodlust_health`. Every target is base-career or cross-career — no DLC-career-specific templates. The audit conclusion stands: reworks are global table patches and harmless to non-owners (they can't equip the career, so the patched buff template never attaches). No changes needed in this file.

## 0.2.19-dev (2026-05-17)

### Added: Per-character experience level override

Five numeric widgets under a new **Character Experience Level** group — one per hero (Bardin, Kruber, Kerillian, Saltzpyre, Sienna). `0` = use real XP (default), `1`–`35` = force that character to report exactly that level everywhere.

Single chokepoint: hook `ExperienceSettings.get_experience(hero_name)` and return `ExperienceSettings.get_total_experience_required_for_level(override)` when the user has set a non-zero value for that hero. Every downstream consumer — the inventory level badge, character-select tile, mission-spawn `level` network field, network_server's hero-level check, scoreboard, even chest reward level — reads through `get_experience`, so one hook covers all of them and the computed `level` / `progress` / `extra_levels` stay internally consistent.

Per character (not per career): VT2 stores XP keyed on `hero_attributes["dwarf_ranger" | "empire_soldier" | "wood_elf" | "witch_hunter" | "bright_wizard"]`, so all four careers under one hero share the same XP and therefore the same level. Use case: testing host/client features that gate on level (e.g. Athanor unlock at 11, weave forge access, etc.) without grinding XP on a fresh modded-realm character.

Modded realm only by definition — Workshop mods can only execute under `script_data["eac-untrusted"]`. The hook never writes to the backend.

## 0.2.18-dev (2026-05-16)

### Fixed: Talent-swap dropdown options rendering as `<<<<<...None (default)>>>>>` (nested brackets)

After v0.2.14 added per-option `talent_swap_option_*` localization keys, the first dropdown rendered correctly but every subsequent dropdown wrapped the resolved text in another pair of angle brackets — the 20th career's dropdown showed nineteen layers (`<<<<<<<<<<<<<<<<<<<None (default)>>>>>>>>>>>>>>>>>>>`).

Root cause: VMF's `options.lua localize_dropdown_data` mutates each option's `text` field in place (`option.text = mod:localize(option.text)`). All 20 dropdowns shared a single `local talent_swap_options = {…}` table reference, so:

1. First dropdown registered → `option.text` was `"talent_swap_option_none"` → mod:localize → `"None (default)"`.
2. Second dropdown registered → same physical table → `option.text` is now `"None (default)"` (not a key) → mod:localize falls back to `"<None (default)>"`.
3. Third dropdown → `"<<None (default)>>"`, and so on through the 20th.

Replaced the shared `talent_swap_options` table with a `_talent_swap_options()` factory function that returns a freshly-built table on every call. All 20 dropdowns now invoke the factory at widget construction so each gets its own option list to mutate.

This pattern is documented in `enemy_tweaker_data.lua:17-24`, which spells out the identical trap; the doc-comment is referenced in the new factory's header so the next person reading this file sees the rule.

## 0.2.17-dev (2026-05-16)

### Fixed: Boot-time `string.format` crashes from un-escaped `%` in localization strings

Four widget labels were crashing at boot when VMF resolved them through the localization → `string.format` pipeline: `rework_dr_ranger_attack_speed_5_to_10`, `rework_we_maidenguard_crit_chance_5_to_10`, `rework_wh_zealot_power_5_to_10`, `rework_wh_bountyhunter_double_shotted_80`. Each contained literal percent signs (`+5%`, `80%`, etc.) that `string.format` interpreted as malformed format directives.

Per `feedback_vt2_localize_string_format_pipeline.md`, any localization string that gets fed through `string.format` (talent description tooltips, VMF widget labels at registration, the chaos_wastes_tweaker Localize-hook descriptions) must escape literal `%` as `%%`. The escape collapses back to a single `%` after formatting.

Swept the entire `career_tweaker_localization.lua`: every raw `%` in user-facing strings is now `%%`. Beyond the four flagged labels, this also covered their `_description` siblings and three pre-existing strings that contained un-escaped percents (`rework_general_stagger_thp_description`, `rework_es_mercenary_hellborgs_tutelage_description`, `rework_wh_zealot_smite_random_crits_description`) — those weren't crashing at boot, presumably because tooltips render lazily, but they were the same bug waiting to fire on hover.

## 0.2.16-dev (2026-05-15)

### Added: Three "double the 5% talent" reworks

Three new toggles, all following the same pattern: a career-specific buff template's percent doubled from 5% to 10%, with the in-game talent tooltip rewritten in-place so the displayed value matches.

| Toggle | Career | Talent | Buff template / field | 0.05 → 0.10 |
|--------|--------|--------|-----------------------|--------------|
| `rework_wh_zealot_power_5_to_10`              | Zealot (Victor)         | row-1 +5% Power         | `victor_zealot_power.buffs[1].multiplier`            | flat +Power stat_buff |
| `rework_dr_ranger_attack_speed_5_to_10`       | Ranger Vet (Bardin)     | row-2 +5% Attack Speed  | `bardin_ranger_attack_speed.buffs[1].multiplier`     | flat +Attack Speed stat_buff |
| `rework_we_maidenguard_crit_chance_5_to_10`   | Handmaiden (Kerillian)  | row-2 +5% Crit Chance   | `kerillian_maidenguard_crit_chance.buffs[1].bonus`   | flat +crit_chance stat_buff (uses `bonus` field, not `multiplier`) |

Menu placement: each lands under `Talent Reworks > Rework: <Character> > Rework: <Career>`. The Zealot toggle joins the existing Smite rework under `Saltzpyre > Zealot`; the Ranger Veteran and Handmaiden toggles create new `Rework: Bardin` and `Rework: Kerillian` top-level character subgroups.

#### Implementation

All three reuse a new `_build_stat_buff_rework(talent_name, buff_field, new_value)` factory in `career_tweaker_balance.lua`. The factory returns a `{ patches, custom_apply, custom_restore }` triple that:

1. Patches `BuffTemplates[talent_name].buffs[1][buff_field]` (runtime effect — applied/restored by the existing patch engine).
2. Walks `TalentIDLookup[talent_name]` to find the talent entry and overwrites `Talents[hero_name][talent_id].description_values[1].value` (tooltip text).

The factory assumes the buff template name matches the talent's `name` field and that `description_values[1]` is the relevant tooltip slot — verified for all three. Career-specific templates only, so patches don't bleed into other careers' equivalents (every career has its own `<career>_attack_speed` / `<career>_power` / `<career>_crit_chance` variant rather than a shared template — the shared `power_level_unbalance` template used by the level-15 row is NOT what these reworks touch).

#### Pyromancer skipped

Original request included Pyromancer's "5% attack speed" talent. Audit confirms Pyromancer (sienna_adept) has no flat 5% Attack Speed talent on any of her 6 rows — her only AS talent is `sienna_adept_attack_speed_on_enemies_hit_buff` at level 25 (15% AS for 5s after hitting 4+ enemies in one swing, conditional), and her flat passives are all overcharge-related. Toggle deferred pending clarification.

#### Field-name caveat

The `bonus` vs `multiplier` distinction is load-bearing. The `critical_strike_chance` stat_buff consumes `bonus` additively at the `buff_extension` level (`buff_extension.lua:196`), while `power_level` and `attack_speed` stat_buffs consume `multiplier`. Picking the wrong field silently no-ops the runtime effect (the tooltip still updates because that's driven by `description_values`, not the buff field). Reflected this in the factory call sites.

## 0.2.15-dev (2026-05-15)

### Changed: Minimum THP-on-kill floor 1 → 1.5

Audit of `BreedTweaks.bloodlust_health` (breed_tweaks.lua:594) shows the actual vanilla minimum for combat breeds is `skaven_horde = 1` (slaves). All other hordes are already at 1.5 (`beastmen_horde` = ungor, `chaos_horde` = fanatic); roamers are 2–3; everything above is much higher. The pre-existing floor of 1 was therefore a no-op — slaves already met it, and the only sub-1 entries (`breed_chaos_greed_pinata` and `breed_training_dummy`, both 0) are props you don't kill for THP.

Bumped `_MIN_THP_ON_KILL` to 1.5 so slaves lift to match the other hordes; nothing else changes (the clamp only fires when `v < floor`, and every other breed's vanilla value already exceeds 1.5). The CHANGELOG/localization claim that "slaves/hordes sit at 0..1" was incorrect — slaves are exactly 1, hordes are 1.5 — so the toggle description is rewritten to reflect the actual values.

## 0.2.14-dev (2026-05-15)

### Fixed: Talent-swap dropdown options wrapped in `<<...>>` brackets

Every talent-swap dropdown (`talent_swap_<career>`) listed its options as `{ text = "None (default)", value = "none" }` etc. — raw English strings. VMF resolves the `text` field as a localization key via `mod:localize(key)` and, when the key isn't registered, falls back to wrapping it in `<<key>>` markers so authors notice the missing entry. The fallback was firing on every option in every talent-swap widget, so the dropdowns rendered as `<<None (default)>>`, `<<Ironbreaker (Bardin)>>`, etc.

Replaced each `text = "<display string>"` with `text = "talent_swap_option_<value>"` and registered the matching `talent_swap_option_*` entries in `career_tweaker_localization.lua` (21 keys: one for `none` + one per career). Display text is unchanged; the brackets are gone.

## 0.2.13-dev (2026-05-15)

### Added: Bounty Hunter Double-Shotted rework — 80% refund on headshot

New checkbox under `Talent Reworks > Rework: Saltzpyre > Rework: Bounty Hunter > Rework: Double-Shotted — 80% refund on headshot`.

Vanilla Double-Shotted (`victor_bountyhunter_activated_ability_railgun`): when the Locked And Loaded shot connects as a headshot on its first target, `victor_bounty_hunter_reduce_activated_ability_cooldown_railgun` (buff_templates.lua:3615) adds the delayed buff `victor_bountyhunter_activated_ability_railgun_delayed_add`, which on removal (0.25s later) calls `career_extension:reduce_activated_ability_cooldown_percent(buff.multiplier)`. The template `multiplier` is 0.6, so the refund is 60%. With this rework on, the value is patched to 0.8 — 80% refund.

The visible "60%" in the inventory talent tooltip is read from `Talents.victor[talent_id].description_values[1].value`, set at game-init from `buff_tweak_data.victor_bountyhunter_activated_ability_railgun.multiplier`. By the time VMF mods run, that value is already frozen on the talent entry, so the rework's `custom_apply` walks `TalentIDLookup["victor_bountyhunter_activated_ability_railgun"]` to find the talent table and rewrites `description_values[1].value` in place; `custom_restore` puts it back. The tooltip doesn't refresh live — players need to close and re-enter the talent panel after toggling (same caveat as Hellborg's Tutelage).

The patches engine already supports `{ buff = ..., field = ..., value = ... }` entries alongside custom_apply/custom_restore on the same rework, so no engine changes were needed.

## 0.2.12-dev (2026-05-15)

### Added: "Talent Reworks" menu structure (Talent Reworks > General | Rework: \<Character\> > Rework: \<Career\> > Rework: \<Talent\>)

Replaced the flat "Talent Balance Changes" group with a nested hierarchy so future reworks slot in by character/career instead of accumulating in a wall of checkboxes. Every submenu and toggle is prefixed `Rework: ` so the player always knows which top-level menu they're in:

- **General** — cross-career toggles (Stagger THP, Minimum THP-on-kill)
- **Rework: Kruber** > **Rework: Mercenary** > Hellborg's Tutelage (new — see below)
- **Rework: Saltzpyre** > **Rework: Zealot** > Smite (split from old combined Zealot/Merc toggle), **Rework: Witch Hunter Captain** > Extended parry window

Setting IDs renamed to match the new naming scheme (mod is pre-release; no user-state migration needed):

| Old | New |
|-----|-----|
| `balance_zealot_merc_allow_random_crits` | (split) `rework_wh_zealot_smite_random_crits` + new `rework_es_mercenary_hellborgs_tutelage` |
| `balance_whc_parry_extended_window`      | `rework_wh_captain_parry_window` |
| `balance_stagger_thp_rework`             | `rework_general_stagger_thp` |
| `balance_thp_kill_minimum`               | `rework_general_thp_kill_minimum` |

`on_setting_changed`'s pattern updated from `^balance_` to `^rework_` to match.

### Added: Hellborg's Tutelage rework (Mercenary)

New checkbox under `Talent Reworks > Rework: Kruber > Rework: Mercenary > Rework: Hellborg's Tutelage`.

Vanilla Hellborg's Tutelage (the `markus_mercenary_crit_count` talent) grants a guaranteed crit every 5 melee hits but attaches the perk `{ "no_random_crits" }`, which `ActionUtils.is_critical_strike` reads to force the random-crit roll to false. The rework keeps the guaranteed-every-5 cadence intact but flips the trade-off: random crits are re-enabled, and in exchange the random crit chance is reduced by a flat 10% (0.10) for the duration of the talent.

Implementation is hook-based and idempotent (each hook reads `mod:get(...)` on every call, so toggling takes effect on the next attack):

1. **`TalentExtension.has_talent_perk`** — `self._career_name == "es_mercenary"` branch returns `false` for `"no_random_crits"` when the toggle is on, so `is_critical_strike` falls through to the normal `get_critical_strike_chance` path. The same hook also handles the Zealot Smite rework (`wh_zealot` branch), so the two toggles don't bleed across careers.
2. **`ActionUtils.get_critical_strike_chance`** — when the player is on Mercenary, has Hellborg's Tutelage selected (`talent_ext:has_talent("markus_mercenary_crit_count")`), and the toggle is on, subtracts 0.10 from the post-buff chance with a floor of 0. Mercenary's base 5% crit chance zeros out at the floor but crit-chance stacking (weapon traits, properties, bench buffs, talents like Bloodlust) still pushes it positive. Hooked table-form (`ActionUtils` is a plain global, not a class) with a load-order guard.
3. **`_G.Localize`** — overrides the `markus_mercenary_crit_count_desc` key with `"Critical Strike every %d melee hits. Random Critical Strike chance reduced by 10%%."` while the toggle is on, so the in-game talent description in the inventory talent panel matches the new behavior. `%%` because the post-Localize string is re-fed through `string.format` with `description_values` per `feedback_vt2_localize_string_format_pipeline.md`.

The Zealot Smite half of the old combined `balance_zealot_merc_allow_random_crits` toggle is preserved as `rework_wh_zealot_smite_random_crits` (under `Rework: Saltzpyre > Rework: Zealot`); its semantics are unchanged — random crits re-enabled with no chance penalty. The Mercenary half is now the new Hellborg's Tutelage rework instead.

## 0.2.11-dev (2026-05-12)

### Changed: Stagger THP Rework dialed back from +100% to +50%

In-game testing showed the v0.2.9 `base_value` 1 → 2 (+100%) was too strong. Dropped to 1.5 (+50%): light/medium/heavy stagger now heal 0.375 / 1.5 / 3 THP per target instead of 0.5 / 2 / 4. The `max_targets = 3` cap stays. Perfect heavy-stagger swing across 3 enemies now tops out at 9 THP (was 12); typical medium-stagger swing across 3 caps at 4.5 THP (was 6).

### Changed: "Normalize THP-on-kill" → "Minimum THP-on-kill"

The v0.2.8 power-law normalization also overshot in-game. Replaced the toggle entirely with a simpler floor: when on, every breed's `bloodlust_health` gets clamped to at least `_MIN_THP_ON_KILL = 1`. Trash kills (vanilla 0..1) always pay out 1 THP; elites/specials/monsters keep their vanilla values untouched. Setting key renamed `balance_thp_breed_normalize` → `balance_thp_kill_minimum` (mod is private — no user-state migration needed). Display name now "All careers: Minimum THP-on-kill".

The same snapshot/restore mechanics carry over (record originals into `saved.breed_thp_originals`, walk on disable). Only breeds whose vanilla value is below the floor get touched, so restore only walks the changed set.

## 0.2.9-dev (2026-05-09)

### Changed: "Double THP on stagger" → "Stagger THP Rework"

Renamed the 0.2.7 stagger toggle and tightened it. The new behavior keeps the doubled `base_value` (1 → 2) but also drops `max_targets` from 5 → 3 — both fields patched on `BuffTemplates.thp_tank.buffs[1]`. Caps update from "≤20 THP per perfect heavy swing" to "≤12 THP per perfect heavy swing"; a typical medium-stagger swing now tops out at 6 THP instead of 10. Setting key renamed `balance_thp_on_stagger_doubled` → `balance_stagger_thp_rework` (mod is private, recently deployed — no user-state migration needed). Display name now "All careers: Stagger THP Rework".

The patches engine already supports multiple `{ field, value }` entries per setting (one apply/restore loop iterates `def.patches`), so the second patch slots in without engine changes.

## 0.2.8-dev (2026-05-08)

### Added: "Normalize THP-on-kill across enemy types" balance toggle

New checkbox under "Talent Balance Changes": `balance_thp_breed_normalize`. Compresses every breed's `bloodlust_health` (the per-enemy THP-on-kill amount used by Heal-on-Kill weapon traits, the Bloodlust CW trait, the Warrior Priest aftershock heal, and any other talent/buff that reads `breed.bloodlust_health`) toward a fixed pivot using a power law:

> `new = pivot × (vanilla / pivot) ^ n`, with `pivot = 10` and `n = 0.5`.

Vanilla THP-on-kill spans 1 (slave) → 50 (monster), a 50× spread. After normalization the spread collapses to roughly 3 → 22:

| Vanilla | Normalized |
|---------|------------|
| 1 (slave)            | ~3.2  |
| 1.5 (horde)          | ~3.9  |
| 2 (skaven roamer)    | ~4.5  |
| 3 (gor / chaos roamer) | ~5.5 |
| 8 (skaven elite/special) | ~8.9 |
| 10 (chaos special)   | 10    |
| 15 (chaos elite)     | ~12.2 |
| 30 (chaos warrior)   | ~17.3 |
| 35 (chaos bulwark)   | ~18.7 |
| 50 (monster)         | ~22.4 |

Implementation lives in `career_tweaker_balance.lua` as a `custom_apply` / `custom_restore` pair on `BALANCE_MODS.balance_thp_breed_normalize`. On apply, iterates `Breeds`, snapshots each breed's `bloodlust_health`, and overwrites with the transform; on disable / re-toggle the snapshot is written back. Each breed file copies its number out of `BreedTweaks.bloodlust_health` at game-load time (e.g. `breed_chaos_warrior.lua:134`), so we have to mutate every breed table directly — patching the central `BreedTweaks.bloodlust_health` table after load does nothing.

Pivot and exponent are intentionally fixed (no sliders) per the user's "just a reasonable tuning that I'll find via testing" preference. Tuning lives in `custom_apply` body.

## 0.2.7-dev (2026-05-08)

### Added: "Double THP on stagger" balance toggle

New checkbox under "Talent Balance Changes": `balance_thp_on_stagger_doubled`. Patches `BuffTemplates.thp_tank.buffs[1].base_value` from `1` → `2`, doubling the THP gained per stagger across all Heal-on-Stagger talents (every career that has one). Light / medium / heavy stagger now heal `0.5 / 2 / 4` THP per target instead of `0.25 / 1 / 2`. `max_targets` is unchanged at 5, so a perfect heavy-stagger swing across 5 enemies caps at 20 THP and a typical medium-stagger swing caps at 10 THP. The push branch (`is_push`) goes through the same `base_value * push_modifier` path so it scales with the toggle (push_modifier = 0.5, max push heal now 2 THP at heavy stagger).

This is the first balance entry that actually uses the `patches` field of `BALANCE_MODS` — the prior two (`balance_zealot_merc_allow_random_crits`, `balance_whc_parry_extended_window`) are hook-based with empty `patches{}`. Removed the stale "currently dead code" REVIEW comment now that the engine has a live consumer.

The Heal-on-Stagger nerf was part of [Patch 3.1 / "Big Balance Beta Update #1"](https://forums.fatsharkgames.com/t/pc-vermintide-2-the-big-balance-beta-update-1/28267) ("Reduced the temp health gained from the stagger talents… should now be more in line with the other temp health talents"). Fatshark didn't publish exact pre-nerf numbers; doubling chosen by user feel — pre-nerf was widely felt as ~2x current, which was slightly OP.

## 0.2.4-dev (2026-05-01)

### Changed: Migrated to VMB build pipeline

Moved from the raw Stingray SDK build (`crt.mod`, `settings.ini`, `lua_preprocessor_defines.config`, `.build/OUT/`) to VMB (`career_tweaker.mod`, `itemV2.cfg`, `bundleV2/`). Workshop ID `3716286199` and internal mod ID `"crt"` preserved — existing user settings are unaffected. `visibility` remains `"private"`.

## 0.2.3-dev (2026-04-29)

### Fixed: Dropdown options showing <<>> brackets

VMF dropdown `text` fields must be literal display strings, not
localization keys. Changed all talent swap dropdown options from
localization key references (e.g. `"cname_dr_ironbreaker"`) to inline
strings (e.g. `"Ironbreaker (Bardin)"`). Removed unused localization
entries for dropdown options.

### Removed: Melee-in-ranged-slot feature

Removed the "Allow Melee in Ranged Slot" checkbox and all associated
logic (`apply_slot_settings`, `_original_slot_2_allowed`). This feature
doesn't belong in career_tweaker.

### Removed: Career action injection checkbox

Removed the "Inject Career Actions on Unlocked Weapons" checkbox. This
setting was always handled by weapon_tweaker; the checkbox here was
non-functional.

## 0.2.2 (2026-04-29)

### Fixed: Balance module not found — missing from resource package

`career_tweaker_balance.lua` was not registered in `career_tweaker.package`,
so the Stingray compiler never bundled it. `mod:dofile` failed with
`Resource not found`, leaving `balance` as nil. Every subsequent
`on_game_state_changed` call crashed with `attempt to index upvalue
'balance' (a nil value)`, spamming errors on every state transition.

Fix: Added the file to `resource_packages/career_tweaker.package`.

### Fixed: Cascading crash when balance module fails to load

If `mod:dofile` for the balance module fails for any reason, the mod now
logs the error and substitutes a no-op stub so lifecycle hooks
(`on_game_state_changed`, `on_setting_changed`, `on_disabled`) continue
working. Previously a single load failure cascaded into errors on every
game state transition.

## 0.2.1 (2026-04-29)

### Fixed: Empty VMF groups crash mod options init

VMF requires groups to have at least 1 sub_widget. Empty placeholder groups
for Bardin, Kruber, Kerillian, and Sienna caused `new_mod` to fail options
initialization with: `[widget "balance_kruber_group" (group)]: must have at
least 1 sub_widget`. Removed empty character sub-groups; balance checkboxes
are now flat under the "Talent Balance Changes" group until they have enough
entries to warrant sub-grouping.

## 0.2.0 (2026-04-29)

### Added: Talent balance modification framework

New data-driven system for toggling per-talent balance changes via VMF
checkboxes. Supports both simple BuffTemplates field patches and hook-based
modifications. All changes default to off.

Initial balance mods:
- **Zealot/Merc: Allow random crits with guaranteed crit talent** — The
  "crit every 5 hits" talent normally disables all natural random crits via
  the `no_random_crits` talent perk. This toggle suppresses that perk so
  natural crits can proc between guaranteed ones. (Hook on
  `TalentExtension.has_talent_perk`)
- **WHC: Parry crit talent doubles parry window** — Extends the parry
  timing window from 0.5s to 1.0s. (Hook on `ActionBlock` and
  `ActionMeleeStart` `client_owner_start_action`)

### Fixed: Talent picker UI not refreshing after swap

Hooks `HeroWindowTalents.on_enter`/`on_exit` to track the live window
instance. After `apply_talent_swaps()`, calls `_update_talent_sync()` on
the tracked instance to force the UI to re-read swapped talent trees.

### Fixed: Weapon-ability crash on cross-character swap

Replaced `pcall`-based crash recovery with a deterministic skip list.
Careers with weapon-based abilities (e.g. Grail Knight) skip the ability
swap when the target is a different character. Talent tree swap still
applies. Logs an info message instead of silently catching an exception.

### Changed: Deleted incorrect entry point

Removed `career_tweaker.mod` — the correct entry point is `crt.mod`
(registers as `"crt"` matching all `get_mod("crt")` calls). Having both
caused double-registration errors.

## 0.1.1 (2026-04-29)

### Added: Workshop upload

First Workshop upload as private item (ID 3716286199). Fixed `item.cfg`
to use relative paths and private visibility. Added Workshop ID to
`deploy_all.ps1` and `CLAUDE.md`.

## 0.1.0-dev (2026-04-24)

### Added: Version logging

Mod now logs `Career Tweaker v<version> loaded` on init so the running version can be verified in the console log.
