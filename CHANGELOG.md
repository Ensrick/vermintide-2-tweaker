# Changelog

## 2026-08-11 - Weapon Tweaker reaches the structural completion target (#1159)

Tweaker: Weapons 0.12.303-beta and 0.12.304-dev extract the canonical
cross-character transform transaction and the engine-fatal attachment and
animation guards into two explicit mirrored owners. The paired inventory and
husk visibility repair joins the existing in-game 3P swap owner. Engine-free
Lua 5.1 coverage pins receiver/hand routing, owner/bot/husk fan-out,
first-person boundaries, `skip_sync` forwarding, and non-mutating attachment
fallback. Stable/dev entries fall to 1,328/1,487 nonblank lines, their required
owner inventory rises from eight to ten, and both machine contracts now mark
the Weapon Tweaker structural phase complete.

## 2026-08-11 - CIM Dev reaches the structural completion target (#1159)

Crafting in Modded 0.8.121-dev extracts boot/regression infrastructure, forged
item persistence plus backend restore, and issue #278/#371/#598 loadout wire
safety into three explicit owners. Engine-free Lua 5.1 coverage pins live store
rebinding, backend callback order, sender-only rarity substitution, schema
refusal, and unknown-id predecode failure. The entry falls from 2,353 to 1,433
nonblank lines, the required-owner inventory rises from ten to thirteen, and the
machine contract marks the CIM Dev structural phase complete.

## 2026-08-11 - Cosmetics structural phase reaches completion target (#1159)

Tweaker: Cosmetics 0.9.207-dev extracts exact-instance offhand state/restore,
the shared authored offhand paint transaction, read-only offhand diagnostics,
bounded glow diagnostics, and the Deus mission-only precedence policy into five
explicit owners. Lua 5.1 tests pin idempotent merge, bounded restoration,
fail-closed dual validation, and mesh-mismatch refusal. The entry falls from
2,051 to 1,494 nonblank lines, the required-owner inventory rises from 32 to 37,
and the machine contract marks the Cosmetics structural phase complete.

## 2026-08-11 - Cosmetics remote-husk transaction gains explicit owners (#1159)

Tweaker: Cosmetics 0.9.206-dev moves the remote-husk identity/spawn policy into
`_cos_la_husk_identity_runtime.lua` and the single remote weapon-wield
transaction into `_cos_husk_wield_runtime.lua`. Executable Lua 5.1 coverage
pins identity precedence, spawn replay, vanilla error restoration, eight-return
preservation, and bounded glow/LA reconciliation. The entry falls from 2,488 to
2,051 nonblank lines and the required-owner inventory rises from 30 to 32.

## 2026-08-11 - Cosmetics crosses the entry hard limit (#1159)

Tweaker: Cosmetics 0.9.205-dev moves the shared attachment/preview spawn
boundary into `_cos_spawn_boundary.lua` and the optional Moonfire impact hooks
into `_cos_moonfire_puff_runtime.lua`. Executable Lua 5.1 coverage preserves
registration totals, ordering, narrow missing-hat fallback, dependency refresh,
and the no-double-puff WT gate. The entry falls from 2,646 to 2,488 nonblank
lines, crossing below the 2,500 hard limit; it remains above the 1,500
structural-completion target.

## 2026-08-11 - Cosmetics item presentation gains one runtime owner (#1159)

Tweaker: Cosmetics 0.9.204-dev moves exact-instance item-card resolution, the
single `UIUtils.get_ui_information_from_item` hook, and the late Hold-Tab peer
adapter into `_cos_item_presentation_runtime.lua`. The two-phase owner preserves
the historical post-LA receiver boundary, refreshes action-time dependencies on
reinstall, and adds no transport or lifecycle surface. Lua 5.1 coverage pins
vanilla return preservation, hook ownership, late peer-cache refresh, and source
cardinality. The entry ceiling falls from 2,915 to 2,646 nonblank lines.

## 2026-08-11 - Cosmetics gains one bounded frame owner (#1159)

Tweaker: Cosmetics 0.9.203-dev moves its existing per-frame coordination into
`_cos_update_scheduler.lua` without changing tick order, retry limits, or wire
shape. Executable Lua 5.1 tests pin the scheduler boundary, action-time state,
bridge initialization, state-pull cadence, and shared LA queue rebinding. The
Cosmetics entry ceiling falls from 3,207 to 2,915 nonblank lines.

## 2026-08-11 - Chaos Wastes peer diagnostics gain one owner (#1159)

Chaos Wastes Tweaker Dev 0.7.337-dev moves peer manifest construction,
transport, reassembly, diff logging, and `/peers` into one dependency-injected
owner without changing its wire contract or registration order. Executable
Lua 5.1 coverage pins the boundary, and the entry-size ceiling falls from 4,303
to 4,114 nonblank lines.

## 2026-08-11 - Worktree cleanup trusts its proven base (#1257)

The approved worktree lifecycle helper now deletes a branch only after proving
it is merged into `origin/master`, without asking Git to re-evaluate safety
against the caller's potentially stale checked-out branch. Its dual-host
self-test pins the fail-closed ancestry boundary, and an integration replay
closed an exact-`origin/master` fixture from the stale primary checkout.

## 2026-08-01 - Accessory property writes retain their layer (#959)

Crafting in Modded 0.8.109-dev fixes the mutation seam omitted by the first
accessory-isolation repair. Health (and every other property) can now be applied
independently to Necklace, Charm, and Trinket even when a sibling accessory has
already filled that property's cap. The same pure policy now owns write
admission, both capacity checks, display, removal, and Clear; executable
coverage performs the actual sibling-layer write instead of manually creating
the expected fixture.

## 2026-08-01 - Atomic remote Musket hand selection (#474/#786)

Character Weapon Variants 0.1.477-dev now proves every authored remote-husk
hand unit and its donor material before changing vanilla's hand-selection
table. A cold Old Musket render preserves the visible base Handgun and queues
one bounded lease; a resident replay selects the custom Musket atomically.
Engine-free coverage reproduces both phases and the #660 appearance contract
now names the husk adapter as an owner. Co-op runtime verification is pending.

## 2026-07-22 - Configurable Chaos Wastes starting shrine (#458)

Chaos Wastes Tweaker Dev 0.7.308-dev adds an opt-in shrine at the exact start
node. The host controls boon and miracle counts, a stepped 0-200% price, and an
unlimited or 1-8 purchase limit per hero and run. The implementation prepares
its synthetic shop before vanilla full-state sync, fails closed if that exact
context is malformed, leaves every later shrine on the vanilla path, and
composes with the existing bot-boon purchase hook. Twelve focused Lua tests pin
the policy and lifecycle boundaries before in-game verification.

## 2026-07-22 - Atomic Chaos Wastes profile/runtime evidence (#919)

The paired logs could not bind the active Mod Tweaker profile to the local and
host-effective values consumed when a Chaos Wastes run starts; one was a client
correctly consuming different host settings. Tweaker: GUI now exposes a bounded
post-commit observer per tab, and Chaos Wastes Tweaker records one atomic line
covering profile slot, peer role, effective source, starting coins, Rotten
Miasma selection/disable state, and player-facing starting-boon lists at every
relevant boundary. No gameplay behavior changes until this evidence identifies
the failing layer.

## 2026-07-19 - Exact per-instance Loremaster inventory icons (#883)

Cosmetics Tweaker 0.9.160-dev now resolves inventory-card icons from the exact
backend item's saved Loremaster selection and skin. Direct Armoury keys are
validated against LA's authored `SKIN_LIST`; exact skins precede bridge
representatives, while unknown identities fail closed without mutating global
icon tables. Bounded file-only diagnostics and unit/appearance contracts cover
the regression. Source is prepared for the serialized bundle build and still
requires merge/deployment before in-game verification.

## 2026-07-19 - Blightreaper visible-scale restoration (#712)

The WOC `0.1.33-dev` log proves its durable writer retained the requested pose
on the correct render node, but also proves the node's native scale is 100 and
the writer replaced it with absolute 0.9. WOC now resolves the authored 0.9 as
a baseline multiplier (90 in the observed units) before issuing the absolute
atomic pose. This draft is source-tested only and still needs the serialized
bundle/build/deploy step.

## 2026-07-19 - Dev localization resource contract (#824)

Tweaker: GUI dev 0.2.296-dev now loads its own localization resource in the
runtime format check and treats an unreachable localization table as a failed
check. The static dofile/package gate now recognizes colon-form, dot-form, and
protected dot-form module loads so the same resource-boundary mistake is caught
before deployment.

## 2026-07-18 - Canonical hidden build-only pipeline (#832)

`tools/ship/ship.ps1 -BuildOnly` now provides the serialized, no-window VMB build needed to generate a release bundle before the source/bundle atomicity gate can pass. Build-only preflight defers only that circular gate, runs it immediately after generation, preserves the ship claim for the eventual full release, and exits before deploy, Workshop upload, GitHub release, or issue lifecycle changes.

## 2026-07-18 - Headless VMB process boundary (#829)

`tools/ship/ship.ps1` now starts VMBLauncher with explicit no-window process flags and redirected output instead of PowerShell's raw native call operator. Both the identity probe and full release preserve exit-code/output handling without allocating visible console windows in desktop automation. The ship self-test executes the boundary and passes under Windows PowerShell 5.1 and PowerShell 7.

## 2026-07-18 - Chaos Wastes host graph live reconciliation

Chaos Wastes Tweaker dev 0.7.299-dev addresses #136 at the proven graph-authority seam. Clients still receive the host's resolved graph through the existing paced `ct_graph_snapshot_chunk` pipeline, but now immediately apply the completed snapshot to the live `DeusRunController` graph instead of waiting for the map UI to open. The existing map-open application remains a visual late-safety path.

## 2026-07-17 - Cross-provider career-action clone ownership

Issue #661's live `action_career_dr_3` / `action_career_es_4` conflicts came
from private weapon templates deep-cloning both canonical action rows and the
donor template's WT/CWV/WOC claim metadata. The shared career-action library
now owns one exact-source, idempotent clone-preparation boundary: copied claims
are discarded, donor-proven canonical rows regain `ActionTemplates` identity,
and later foreign replacements remain conflicts. CWV 0.1.445-dev applies the
boundary to every completed private template; WOC 0.1.30-dev reuses it for
Blightreaper; WT beta 0.12.273 and WT dev 0.12.274 carry the exact shared
consumer copy. Lua 5.1 coverage exercises provider load order, repeated
reconciliation, late registration, release, and rollback. In-game verification
is still required; nothing was deployed by this draft change.

## 2026-07-17 - Exact Athanor shield preview ownership

Tweaker: Cosmetics v0.9.143-dev hardens issue #481 at the existing
`BackendUtils.get_item_units` and `LootItemUnitPreviewer.spawn_units` seams.
The latest log proved the Loremaster and Purpure/Azure choices were persisted
under different exact backend items, but also showed an unreadable runtime mesh
being accepted despite a mismatched target. Preview fallback now requires the
same normalized weapon family, saved components must belong to the exact hand
pool, and the queued `spawn_data` unit path is the fail-closed paint authority.
The two intentional Athanor overview previewers remain intact. Offline Lua 5.1
and runtime checks cover cross-item isolation without adding hooks or transport.
This source also preserves the already-uploaded v0.9.142-dev issue #695 backend
readiness guards from the separate public ship worktree; its generated bundle
was not copied or modified here.

## 2026-07-17 - Clean-worktree launcher provenance handoff

Issue #683 centralizes VMBLauncher dependency discovery for the canonical ship
and GitHub-release phases. `ship.ps1` now passes its exact approved executable
path, provenance source, and approval anchor to `publish-release.ps1`; the
release phase revalidates that immutable snapshot before recording the
executable's real version. Direct
release publishing uses the same invoking/configured/primary/environment
candidate set and fails closed when no approved launcher exists. Offline
PowerShell 5.1 and 7 fixtures cover clean external dependencies, invalid paths,
provenance mismatch, missing candidates, and ship-to-release wiring. Full QA
now runs that contract as an explicit blocking matrix under both PowerShell 7
and Windows PowerShell 5.1, so hosted QA cannot pass without exercising the
release-host compatibility boundary. Nothing was built, deployed, uploaded,
or published by this tooling-only change.

## 2026-07-17 - Exact CWV identity for independent remote offhands

Tweaker: Cosmetics v0.9.140-dev and CWV v0.1.444-dev re-derive the missing
remote half of issue #583 from paired-log evidence. CWV exposes its existing
fingerprint-validated per-peer appearance descriptor, and Cosmetics uses that
exact family when validating a received dual-offhand mesh. This replaces the
observed false comparison against the vanilla base family without adding an
RPC, unit-path payload, or permissive fallback. Co-op verification remains
required; nothing was deployed.

## 2026-07-16 - Weapon lifecycle and career-action integration hardening

Weapons of Chaos v0.1.26-dev retains the atomic linked-root pose introduced in
0.1.25-dev, canonicalizes the exact relic unit descriptor before every
spawn/preview consumer, repairs native Shyish package/spawn/contact
damage-to-THP behavior, and supplies every weapon-bound career action. Weapon Tweaker v0.12.268-beta
and v0.12.269-dev use the same provider-neutral all-row action integration for
native ports and CWV templates. Offline/live gates now reject missing lifecycle consumers,
first-row-only ability handling, incomplete action providers, and runtime
resource/contact drift. Co-op verification remains required; nothing was
deployed.

## 2026-07-16 - Blightreaper intrinsic and reusable poison traits

Weapons of Chaos v0.1.23-dev / CIM v0.8.87-dev implement issue #655. The
Blightreaper now displays intrinsic Poisoned Edge and Shyish Health Curse trait
rows, with poison owned by one reusable WOC proc and the Shyish row using the
native death-spirit icon. CIM exposes Poisoned Edge to eligible melee weapons
only through an exact WOC capability, parks it safely when WOC is absent, and
WOC strips protected keys from transient vanilla loadout shadows so custom
trait identifiers never reach peers without WOC. Offline coverage proves
ownership, no double proc, load-order persistence, bounded pool insertion,
wire immutability, and native icon selection.

## 2026-07-16 - Blightreaper property wire crash

Weapons of Chaos v0.1.22-dev fixes issue #654 by stripping WOC-only properties
and traits from the transient vanilla loadout shadow. The live relic remains
unchanged, while `woc_power_vs_order` can no longer reach
`NetworkLookup.properties` during local, broadcast, or hot-join synchronization.

## 2026-07-16 - General Tweaker bot utility crash guard

Tweaker: General DEV v0.2.241-dev restores vanilla's `math.huge` no-ally
sentinel at every GT ally-selection branch and validates non-condition utility
inputs before native arithmetic. The old Creature Spawner-owned no-op guard is
removed; the exact player-follow input is repaired while unknown malformed
actions fail closed at zero utility. Offline and runtime regressions cover the
producer, consumer, and singleton-hook boundaries. Solo in-game verification
remains required; no deployment is part of this commit.

## 2026-07-16 - Blightreaper combat completion and Shyish residency

Weapons of Chaos v0.1.21-dev adds the requested four-light chain and post-heavy
overhead/stab finishers, intrinsic +15% critical chance, armor-capable Greataxe
profiles, exact display-only `+50% Power vs. Order`, and the Executioner Sword
audio dependency while preserving Greataxe impacts. It also fixes the log-proven
Shyish failure by acquiring its verified source-declared DLC package under a
bounded lifetime reference; offline tests cover the resource boundary and
combat contracts.

## 2026-07-16 - Blightreaper Shyish spirits and axe presentation

Weapons of Chaos v0.1.20-dev / issue #632 adds the missing host-authoritative
native Shyish spirit lifecycle for direct and Hagbane poison kills, including
bounded client poison attribution through the existing native buff RPC, native
audio/FX, and green-health-to-THP conversion. It also replaces inherited sword
strike presentation with Greataxe impacts and same-index safe one-handed Axe
swing events. Offline and live contracts cover attribution, bounds, teardown,
source-backed audio, and conversion policy. Co-op in-game verification remains
required; no Workshop deployment is part of this commit.

## 2026-07-16 - Worktree-bound ship pipeline

Issue #647 binds the canonical ship wrapper's existing VMBLauncher `all`
pipeline to the checkout that owns the invoked script. A named OS mutex
serializes the shared ProjectRoot setting; root, `MOD_VERSION`, git commit, and
`published_id` must match before the pipeline starts; and the original global
settings bytes are restored on success or failure. Offline fixtures cover
parallel-lock ownership, cleanup, byte-exact restoration, and each mismatch.
No Workshop deployment is part of this tooling change.

## 2026-07-16 - Descriptor line-ending deploy verification

Issue #646 narrows the canonical ship verifier's equivalence rule to textual `.mod` descriptors: Steam's LF-to-CRLF rewrite no longer fails an otherwise current deployment. Compiled `.mod_bundle` files and every other artifact remain byte-exact. The ship self-test covers LF/CRLF equivalence, real descriptor edits, standalone carriage returns, and bundle newline changes. No Workshop deployment is part of this tooling change.

## 2026-07-16 - Reciprocal Combat Style registry

Career Weapon Variants v0.1.431-dev / issue #645 replaces style-specific
remap/presentation branches with a validated descriptor registry and adds the
source-proven Kruber/Elven Spear and Shield reciprocal family. Unproven axe,
Glaive/Great Axe, one-handed sword, and Elf/Tuskgor spear families remain
unavailable while automatic pre-RPC diagnostics collect at most 32 distinct
owner events per candidate family. Co-op Spear and Shield evidence and the
diagnostic logs remain required; no deployment is part of this commit.

## 2026-07-15 - Enemy lingering-damage lifetime guard

Tweaker: Enemies v0.7.51-dev / issue #640 guards personal-handicap owner and breed classification with `Unit.alive` after a despawned Globadier remained referenced by its poison area and crashed native `Unit.get_data`. Neutral Personal difficulty factors now skip attacker classification entirely; active factors preserve vanilla damage when no living hostile source can be established. Engine-free adversarial coverage and runtime regression `issue640_personal_handicap_unit_lifetime` cover nil, live, deleted, and lingering-source paths. No deployment is part of this commit.

## 2026-07-15 - Encarmine plume and material correction

Tweaker: Cosmetics v0.9.115-dev / issue #612 makes the authored plume alpha-aware and two-sided, corrects the zero-roughness/near-solid-metal response-map decode, and lifts the carmine diffuse while preserving UV layout. Asset hashes, a reproducible Blender exporter, and face/material contract tests harden the visual fix; two-player verification is required.

## 2026-07-15 - Encarmine spawn-only rendering

Tweaker: Cosmetics v0.9.114-dev / issue #612 keeps the custom helmet out of PackageManager-facing item data and substitutes its already-resident red/gold unit only at final preview, attachment, husk, and score spawn sites. Missing dependencies and peers without Cosmetics fail closed to the vanilla Laurel Helm. Two-player visual and fallback verification is required.

## 2026-07-14 - Keep-slot bot takeover

Tweaker: General DEV v0.2.239-dev / issue #247 replaces the disabled owner-destructive AI swap with a bounded keep-slot transaction across Adventure, Chaos Wastes, and Weaves. The human Player/profile/party slot remains authoritative; one normal bot safely yields and regains its exact slot when vanilla filled the party; observer and reclaim use native camera/force-respawn flows; and schema-v2 request/result messages authenticate the sender and converge rejected client settings. Two-player verification remains required; no deployment is part of this change.

## 2026-07-14 - Bot hazard resistance and Ratling-shield diagnostics

Tweaker: General DEV v0.2.237-dev / issue #488 implements the bounded hazard family: host-owned bots gain independent two-second gas and warpfire resistance stacks, with each active prior stack reducing the next matching hit by 20% up to five. It composes through GT's existing final-damage hook without buffs or networking. The separate shield-versus-Ratling request remains mutation-free diagnostics on the existing cover hook, capped at 12 distinct live state shapes, because avoiding cover does not itself prove the BT can wield and sustain block. No deployment is part of this commit.

## 2026-07-14 - Enemy-modifier transitive and live readiness diagnostics

Tweaker: Enemies v0.7.49-dev / issue #453 now proves the full bounded child-buff and named-function contract behind its 15 native modifiers, then reuses the singleton AI post-spawn seam to sample live prerequisite readiness for two distinct breeds per Special, Elite, Boss, and Lord category. The eight-row session cap reports extensions, navigation/state, native breed bans, existing enhancements, and eligible/rejected counts without applying buffs or changing gameplay. Solo diagnostics are armed; implementation remains co-op verification work. No deployment is part of this commit.

## 2026-07-14 - Premium-special AI skeleton compatibility diagnostics

Tweaker: Enemies v0.7.48-dev / issue #452 upgrades the five-skin asset census into an actionable, mutation-free compatibility gate. The structural audit now covers ordinary breed behavior, inventory, wire lookup, base units, and premium attachment node maps. The already-owned post-spawn hook observes each matching ordinary special at most once per session and reports whether its real AI skeleton supplies every owner/source node required by the Versus player mesh, with an eight-node missing sample and five-line session cap. It never spawns, links, or replicates a cosmetic. Solo diagnostics are armed; eventual appearance and peer parity remain co-op work. No deployment is part of this commit.

## 2026-07-14 - Godmode outgoing power and ammo children

Tweaker: General v0.2.227-dev / issue #549 adds default-off 9999-damage and unlimited-ammo children beneath Godmode. Client strike state follows the existing heartbeat to the authoritative host; positive enemy damage is overridden only after vanilla mitigation side effects, while ammo uses an owner-local consumption buff that composes with the independent `/infinite_ammo` command. This also supersedes duplicate request #382. Two-player verification remains required; no deployment is part of this commit.

## 2026-07-14 - Cosmetics exact-item LA persistence and icons

Tweaker: Cosmetics v0.9.99-dev / issue #376 resolves Loremaster-authored inventory icons from the persisted backend item instead of mutating global skin tables. Same-type item instances remain visually independent, missing metadata fails closed to vanilla, and a delayed backend reconciliation drops overrides for deleted items while preserving CIM-forged records during mirror restoration. Solo in-game verification remains required; no deployment is part of this commit.

## 2026-07-14 - Bound close-range bot no-path teleport retries

Tweaker: General v0.2.226-dev / issue #385 identifies vanilla's distance-independent `teleport_no_path` branch as the former unknown trigger. The first path-failure unstick remains intact; repeated no-path teleports below the configured leash are bounded to one attempt per five seconds and now carry exact D1 branch attribution. Solo in-game verification remains required; no deployment is part of this commit.

## 2026-07-13 - Cosmetics independent dual-weapon offhands

Tweaker: Cosmetics v0.9.97-dev / issue #583 makes the normal illusion row authoritative for a dual weapon's main hand and adds one independent offhand row. The same per-instance/per-hand persistence and host-authoritative direct-mesh path now covers native Warrior Priest Dual Skullsplitters and all seven current CWV dual families across preview, local equipment, transition replay, and remote husks. Invalid or stale hand meshes fail closed to the paired main illusion. Two-player verification remains required.

## 2026-07-13 - Saltzpyre Hammer+Shield ownership

Tweaker: Weapons v0.12.232-dev / issue #594 removes Bardin's native Hammer and Shield from Witch Hunter Captain, Bounty Hunter, and Zealot while retaining Kruber's Mace and Shield as the human-faction option. Menu and localization rows are removed, prior `can_wield` mutations are scrubbed, stale backend cache ownership fails closed, and the rule is invariant across CWV absent/active/disabled states. No deployment is part of this commit.

## 2026-07-13 - CWV Imperial Longsword identity continuity

Character Weapon Variants v0.1.398-dev / issue #396 separates the owned **Imperial Longsword** from its **Helmgart Watchsword** illusion and adds a same-mod item-key side channel for the owner identity that vanilla's base-item wire shape discards. Existing vanilla skin and wield RPCs remain authoritative for the exact cosmetic and render timing; receivers validate the marker against the base weapon and clear it when the slot becomes native. Runtime coverage spans initial sync, live resync, post-parity hot join/transition recovery, remote husk resolution, and inventory preview. Two-player verification remains required; no deployment is part of this commit.
## 2026-07-13 - `gui_tweaker_dev` Mod Tweaker magnifier focus correction

Tweaker: GUI v0.2.243-dev / issue #572 scales the native padded inventory magnifier tile to 7/8 (112x112), positions its approximately 28px visible glyph wholly inside Mod Tweaker's 30px search field, and hides only that passive texture while the unchanged full-field hotspot is focused. Text origin and all search transactions remain unchanged. Offline and runtime contracts cover geometry, focus visibility, view wiring, and hotspot preservation. In-game visual confirmation remains under `verify-fix`; no Workshop deployment is part of this commit.

## 2026-07-13 - Post-fix audit for #574

User co-op verification confirms Cosmetics Tweaker v0.9.94-dev preserves exact-instance glow choices across game exit, keeps inventory preview and wielded models consistent, synchronizes peers after weapon swaps, and reconstructs state when a client leaves and rejoins. The shipped explicit-Apply transaction, owner persistence, host-authoritative payload, render fan-out, and bounded local-only join repaint satisfy the issue contract. Post-fix hardening adds host-runnable lifecycle coverage, tier-a source invariants, corrects the stale networking reference, and records the reusable durable-owner/ephemeral-render-state bug class. No gameplay code or Workshop deployment changed.

## 2026-07-13 - Post-fix audit for #582, #584, and #585

User verification closes the WT/CWV native Dual Axes ownership boundary and the Moonfire equipped-slot resource lifecycle fixes. The audit confirms runtime and offline regression coverage, documents native-versus-variant ownership and persistent player-resource rules, corrects the generated name-map owner after Cosmetics extraction, and regenerates the deterministic catalog without forbidden native Dual Axes rows.

## 2026-07-13 - Post-fix audit for #575

User verification confirms Tweaker: GUI v0.2.240-dev aligns the Mod Tweaker numeric caret across clicks, navigation, signs, decimals, and UI scaling. The shipped native-metric implementation and its runtime/offline geometry tests satisfy the behavior contract. Post-fix hardening adds tier-a source invariants for native scaled-font measurement and both live Mod Tweaker presentation call sites, plus an owning regression checklist and BUG_CLASSES entry for renderer-metric drift.

## 2026-07-13 - blocking headless ship preflight

Issue #591 makes the canonical ship path run fast repository QA, offline Lua 5.1 unit tests, and target-mod lint before VMBLauncher can build, deploy, or upload. The ship self-test locks that ordering so a later refactor cannot silently move validation behind Workshop publication. Engine lifecycle, rendering, and multiplayer behavior remain in the in-game verification tier; deterministic transforms and capacity/resource bounds belong in host-runnable tests.

## 2026-07-13 - `cosmetics_tweaker` score-lineup identity isolation

Repo-aggregate entry for Cosmetics Tweaker v0.9.95-dev / issue #513. End-screen LA cosmetics now resolve only from an exact player-controlled profile+career score row with a complete peer/local-player tuple. Bot rows may share their host's network-owner peer but can neither inherit that host's helmet/skin nor purge the host's valid colour state when their skeleton differs. Added offline and runtime regression fixtures for the observed Grail Knight/Sienna/Warrior Priest lineup. CWV score-screen weapon rendering is unchanged. No Workshop deployment.

## 2026-07-13 - `gui_tweaker_dev` native magnifier geometry correction

Follow-up Tweaker: GUI v0.2.242-dev / issue #572. In-game verification exposed that the native magnifier's 128x128 atlas tile had been incorrectly shrunk to a 22px tile, making the artwork inside its transparent padding roughly one quarter size. Mod Tweaker now uses vanilla's exact 128x128, x=-80/y=-4 geometry and x=47 text origin.

## 2026-07-13 - `gui_tweaker_dev` native Mod Tweaker search icon

Repo-aggregate entry for Tweaker: GUI v0.2.241-dev / issue #572. Mod Tweaker now reuses the vanilla inventory search field's atlas-backed `search_filters_icon`, with fixed icon/text clearance in the same scale-aware scenegraph node and no new asset or input target. Runtime regression coverage locks the material, metrics, and unchanged field hotspot. No Workshop deployment.
## 2026-07-13 - `crafting_in_modded_dev` explicit illusion precedence

Repo-aggregate entry for Crafting in Modded v0.8.66-dev / reopened issue #563. Successful Apply Skin completion now atomically records the newest illusion by exact backend ID even when Cosmetics Tweaker owns the local craft bypass, preventing a later mirror-ready rehydrate from restoring an older saved skin. CIM-owned crafts clear stale vanilla overrides and continue using their forge record. Added bounded diagnostics and old-A -> explicit-B -> rehydrate-B regression coverage. No Workshop deployment.

## 2026-07-13 - `character_weapon_variants` replicated cross-access swing audio

Repo-aggregate entry for Character Weapon Variants v0.1.393-dev / issue #398. Cross-access 3P event substitution now occurs before vanilla encodes and sends its animation RPC, so observers receive the same receiver-compatible animation and its authored weapon-foley/exertion timeline as the owner. The change deliberately leaves playback with vanilla rather than manually emitting Wwise events. Added bounded diagnostics and runtime regression coverage; awaiting two-player verification. No Workshop deployment.

## 2026-07-13 - `weapon_tweaker` Moonfire HUD loadout lifecycle

Repo-aggregate entry for Weapon Tweaker v0.12.228-dev / issue #585. Vanilla's energy HUD draws from the career energy extension rather than the equipped item, so drained cross-character energy could remain visible forever after Moonfire was replaced. WT now resets that nonnative stale value once when `slot_ranged` is no longer energy-based, while preserving equipped/stowed Moonfire recharge and native Kerillian handling. No Workshop deployment.

## 2026-07-13 - `weapon_tweaker` Moonfire stowed recharge parity

Repo-aggregate entry for Weapon Tweaker v0.12.227-dev / issue #584. Cross-character Moonfire now detects the energy weapon from the equipped ranged slot, matching native Kerillian recharge while melee is active. Recharge remains owner-authoritative, uses the native 1.5/s rate only for careers with no native rate, and has one shared wielded/stowed application path. No Workshop deployment.

## 2026-07-13 - WT/CWV native Dual Axes ownership boundary

Repo-aggregate entry for issue #582: Weapon Tweaker v0.12.226-dev removes Bardin's native `dr_dual_wield_axes` from Kruber and Saltzpyre availability, while Character Weapon Variants v0.1.391-dev preserves and regression-checks `cwv_es_dual_axes` and `cwv_wh_dual_axes`. WT also strips stale `can_wield` mutations and rejects invalid cached loadouts before falling back to vanilla. No Workshop deployment.

## 2026-07-13 - `weapon_tweaker` Saltzpyre Moonfire presentation

Repo-aggregate entry for Weapon Tweaker v0.12.225-dev / issue #580. Moonfire Bow on WHC, Bounty Hunter, and Zealot now reuses the established Saltzpyre crossbow third-person model, bolt, attachment, preview, husk, and event-remap pipeline. Kerillian and all first-person Moonfire behavior remain untouched. Added bounded diagnostics and runtime regression coverage; awaiting solo and coop verification. Workshop not uploaded.

## 2026-07-13 - `character_weapon_variants` dual-axes cosmetic parity

Repo-aggregate entry for CWV v0.1.390-dev / issue #579. Dual Axes now derives
its illusion set from the canonical Saltzpyre one-handed-axe combination pool,
including DLC-added tiers and the separate default skin. Generated clones keep
the source DLC requirement, both hand meshes, the dual-axes display rig, and
network registration. A runtime regression compares the source and generated
key sets. Full details are in `character_weapon_variants/CHANGELOG.md`.

## 2026-07-13 - `character_weapon_variants` skin reverse-index refresh

Repo-aggregate entry for CWV v0.1.388-dev / issue #567. After deferred variant
owners are registered, CWV now invalidates vanilla's lazy skin-to-weapon cache so
persisted custom skins are indexed from their valid owner combination pools.
Adds `[cwv:567]` diagnostics and regression coverage for the three reported
Sword and Mace, Dual Maces, and Axe and Shield skins. Full details are in
`character_weapon_variants/CHANGELOG.md`.

## 2026-07-13 - `crafting_in_modded_dev` auto-equips new weapons

Repo-aggregate entry for `cim_dev` v0.8.64-dev / issue #562. Added a default-on
option that equips the exact backend ID produced by a successful weapon craft in
the primary or secondary slot selected for crafting. The loadout write targets
the live selected loadout index and is paired with live-avatar equipment
recreation; disabling the option keeps the previous inventory-only behavior.
Accessories are unaffected. Full details and regression coverage are in
`crafting_in_modded_dev/CHANGELOG.md`.
## 2026-05-23 — `weapon_tweaker` per-career weapon toggle reorder

Repo-aggregate entry for `weapon_tweaker` v0.12.71-dev (full details in
`weapon_tweaker/CHANGELOG.md`).

Reordered every career's `unlock_<career>_<weapon>` widget tree (and the
matching localization keys) to a single deterministic rule: natives first
alphabetical → cross-character ports grouped by donor character
(`es → dr → we → wh → bw`) alphabetical within each donor → `*_deus_01`
at end of native and donor clusters. 334 data moves + 406 loc moves;
no setting_id additions/removals, no `default_value` flips, no
per-career inclusion changes.

Ordering rule documented in `_audit_wt_weapon_order.md` §4-5 (repo root).
Peregrinaje was evaluated as the canonical reference (per the user brief)
but rejected — it has no per-character ordering structure to mirror;
audit §1-2 has the full reasoning. The alphabetical-then-donor rule
satisfies the underlying intent (consistent ordering) and is mechanical
to verify and extend.

## 2026-05-21 — Stale-doc banner pass + deploy_*.ps1 reference sweep

Two follow-on cleanups against the doc set after the Section A archive pass.

### Stale-doc banners (5 files)

Added "Stale snapshot — superseded by AUDIT_2026_05_21.md" banner blocks at the top of:

- `REPO_REVIEW.md` (2026-05-01 snapshot)
- `REVIEW_AGGREGATE.md` (2026-05-01 snapshot)
- `CONSISTENCY_REVIEW.md` (2026-05-02 snapshot)
- `WORK_ITEMS.md` (self-stamped 2026-04-27)
- `CROSS_CAREER_PACKAGE_FIX.md` (theory later disproven — added stronger banner line noting current cross-career package handling lives in `AUDIT_2026_05_21.md`)

Original content preserved under the banner; these files retain historical value (file:line citations, pre-VMB pipeline references, diagnostic notes).

### deploy_*.ps1 reference sweep (4 files)

The four shims (`deploy_all.ps1`, `deploy_ct.ps1`, `deploy_gt.ps1`, `deploy_wt.ps1`) were archived to `_archive/legacy_deploy_scripts/` earlier today. Live docs that prescribed running them as the canonical deploy step were updated to point at `VMBLauncher.exe deploy <mod>` (or `all <mod>` for full build+deploy+upload):

- `DEVELOPMENT.md` — directory diagram, Quick iteration loop, Build / Deploy sections, "deploy_all.ps1: variables null inside foreach loop" known-error entry, cosmetics_tweaker Build & Deploy
- `event_tweaker/DEVELOPMENT.md` — "Adding a new mutator" step 4 + Build & deploy section
- `dynamic_cosmetic_portraits/CLAUDE.md` — Build & deploy section
- `dynamic_cosmetic_portraits/DEVELOPMENT.md` — step 8 of the portrait-authoring workflow

Historical references in audit reports (`AUDIT_section_*.md`), memory-doc snapshots (`REPO_REVIEW.md`, `REVIEW_AGGREGATE.md`), `_archive/` READMEs, and per-mod CHANGELOG entries were left alone — they document past state and are correct as historical record.

## 2026-05-21 — Repo archive pass

Section A audit recommendations applied. Created `_archive/` for cold storage
of pre-VMB and otherwise-deprecated content. Nothing on the active build path
moved. See `_archive/README.md` for full per-folder inventory.

### Moved

- `old-backup/` (entire folder, self-flagged for deletion in its own README) → `_archive/old-backup/`. Contents include 7 pre-VMB SDK scripts, 4 loose hex-named bundle files, `tweaker_manual_install.zip`, `lighting_tweaker_20260516/` pre-rename snapshot of `verminious_dreams_lighting`, and the dir's `ANTIGRAVITY.md` / `README.md`.
- `bundleHistory.dat`, `launcher_screenshot.png`, `readme.txt` (root-level stale) → `_archive/root-misc/`.
- `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker_localization.lua.v0726.bak` → `_archive/backups/`.
- `verminious_dreams_lighting/item_preview.png.bak` → `_archive/backups/verminious_dreams_lighting_item_preview.png.bak` (renamed for source-mod traceability).
- `deploy_all.ps1`, `deploy_ct.ps1`, `deploy_gt.ps1`, `deploy_wt.ps1` → `_archive/legacy_deploy_scripts/`. All four moved as one unit because the three shims call `deploy_all.ps1`. Use `VMBLauncher.exe deploy <mod>` directly going forward.

### Kept at root

- `settings.ini` — flagged for review but still referenced in CLAUDE.md's mod-file-structure section; Section A audit marked it **KEEP** because VMB tooling may still read it from cwd. Re-audit after one release cycle.
- All 5 `upload_*.ps1` wrappers — each adds a visibility-regression guard on top of `VMBLauncher.exe upload` (Section A: "highest-value guard of all" for `upload_wt.ps1`).
- `send_keys.ps1` — referenced by `reference_remote_vt2.md`; active dev tool.

### Reference updates

- `CLAUDE.md` — Build Commands section updated to point at `VMBLauncher.exe deploy <mod>` and note the archived shims.

### Flagged but not moved (require further sign-off)

- Legacy `tweaker/` mod tree.
- `cosmetics_tweaker/`'s ~13 ephemeral diagnosis `.md` files (active investigation).
- `_tools/extract_all_bundles.ps1` (active reusable tool).
- `cosmetics_tweaker/.build/`, `cosmetics_tweaker/upload/`, `cosmetics_tweaker/pcb-log.log`, `chaos_wastes_tweaker/boon_loc_dump.txt`, and the three `.lua.processed` SDK artifacts (gitignored — disk clutter only; Section A recommends DELETE, but the user's archival list did not authorize this pass to touch them).

## [2026-05-06] dynamic_cosmetic_portraits v0.1.0 — split from cosmetics_tweaker
### Added
- New standalone mod (Workshop ID `3721036701`, private) wrapping the
  hat/outfit-aware HUD & hero-select character portrait system that
  previously shipped inside `cosmetics_tweaker`.
- 10 portrait sets at split (8 Kruber Mercenary hats + Felix outfit + VT1
  Champion of Ubersreik outfit). v0.1.1 added Plumed Horseshoe (11 total).
- `CHARACTER_COSMETIC_CATALOG.md` moved into the new mod (it's exclusively a
  portrait-authoring reference). The catalog still sources from
  `cosmetics_tweaker/_cos_probe.txt`.
- Per-mod docs: `dynamic_cosmetic_portraits/{CHANGELOG,DEVELOPMENT,TODO}.md`.

### Changed (cosmetics_tweaker → v0.8.0)
- Removed the dynamic-portrait subsystem (~570 lines of Lua, the
  `dynamic_portraits` setting, the `custom_gui_textures` block, 60 package
  declarations, and 90 asset files). The `NewsFeedUI:draw` hot-reload
  safety hook stayed — it protects illusion / LA bridge atlases, not
  portrait materials. See `cosmetics_tweaker/CHANGELOG.md` v0.8.0 entry
  for the per-file delta.

## [2026-04-29] cosmetics_tweaker v0.7.0-dev
### Added
- Unlock All Portrait Frames toggle (modded only, DLC ownership respected)

## [2026-04-29] cosmetics_tweaker v0.6.38-dev
### Added
- DLC ownership gate — skins requiring unowned DLC stay locked even with Unlock All Illusions enabled
- Full modded-realm illusion unlock/apply pipeline (5 hook points, up from 3)

### Fixed
- Locked illusions not applying — missing fake backend IDs, UI locked flag, craft button eac-untrusted gate
- Applied skins stripped on backend refresh — `bypass_skin_ownership_check` now set on local craft

## [2026-04-29] weapon_tweaker v0.10.6-dev
### Added
- Grip offset for Kruber wielding Saltzpyre's Skullsplitter (`wh_1h_hammer`, z +0.15)
- Grip offset for Kruber wielding Saltzpyre's Skullsplitter & Shield (`wh_hammer_shield`, right hand only, z +0.15)
- Per-hand grip offset support — offset entries can specify `hand = "right"` or `hand = "left"` to target one hand only (default both)

### Fixed
- Menu preview grip offsets not applying — `MenuWorldPreviewer._spawn_item_unit` resolved `self._character_name` (hero name like `empire_soldier`) before `_local_career_name()` (career name like `es_mercenary`), so the `es_` prefix never matched
- Menu preview grip offsets applied 4x — `fake_slot` pointed all four unit fields at the same unit, causing the additive offset to quadruple
- `BackendInterfaceWeavesPlayFab.commit` hook error — `commit` method doesn't exist on that class; moved hook to `BackendManagerPlayFab.commit`

## [2026-04-28] cosmetics_tweaker v0.6.19-dev
### Added
- Modded-realm illusion swap — Apply button re-enabled, craft calls intercepted locally instead of PlayFab
- Custom illusion injection system — new weapon skins appear as selectable illusions in the vanilla browser
- "Mace & Bretonnian Shield" custom illusion (Empire mace + GK Bretonnian shield)
- Unlock All Weapon Illusions toggle (modded only)
- Bretonnian Sword & Shield thickness fix (sword only, shield unaffected)
- Loremaster's Armoury bridge toggle

### Fixed
- Craft button sound loop caused by stale `is_held` hotspot flag after fast local craft completion
- Inventory preview scaling both sword and shield on Bretonnian weapons (now right-hand only via `_fields`)
- Illusion browser not applying scale overrides (skin key resolution via `matching_item_key`)

## [2026-04-24 v0.4.0-dev]
### Added
- Two-tier animation redirect system: career-aware redirects for phantom events + standard `has_animation_event` fallback
- Cross-character ranged animation redirects:
  - Kerillian's Volley Crossbow on Saltzpyre careers uses his native volley crossbow animations (`to_repeating_crossbow`)
  - Saltzpyre's Volley Crossbow on Kerillian careers uses her native volley crossbow animations (`to_repeating_crossbow_elf`)
  - Kerillian's Longbow on Kruber careers uses his native longbow animations (`to_es_longbow`)
  - Kruber's Longbow on Kerillian careers uses her native longbow animations (`to_longbow`)
- Cross-character melee animation redirects:
  - Sienna's Crowbill (`bw_1h_crowbill`) uses 1H sword animation on non-Sienna careers; WP uses skullsplitter animation
  - Axes (`to_1h_axe`) redirect to 1H sword on Sienna careers; WP uses skullsplitter animation
  - 1H swords (`to_1h_sword`) redirect to skullsplitter animation on WP
  - Skullsplitter (`to_1h_hammer_shield_priest`) redirects to `to_1h_hammer_shield` on non-WP careers
- New weapon unlocks:
  - Saltzpyre's Volley Crossbow (`wh_crossbow_repeater`) for all 4 Kerillian careers
  - Sienna's Crowbill (`bw_1h_crowbill`) for all non-Sienna careers
  - Saltzpyre's Hammer (`wh_1h_hammer`) for all careers
  - Saltzpyre's Skullsplitter (`wh_hammer_shield`) for Kruber and Bardin careers only (crashes on characters without shield model)
  - Kruber's Mace & Shield (`es_mace_shield`) and Bardin's Hammer & Shield (`dr_shield_hammer`) for Warrior Priest
- Career action injection: non-native weapon templates now receive the career's ability action so career abilities work with cross-character weapons

### Fixed
- Battle Wizard (`bw_adept`) and Pyromancer (`bw_scholar`) career names were swapped — corrected labels and menu order
- Skullsplitter restricted to Kruber/Bardin only — shield weapons crash on characters without shield skeleton support

### Technical
- Career-aware redirect table (`_career_anim_redirect`) handles phantom animation events that exist on all skeletons but only play real animations on native characters
- `invert` flag controls redirect direction: `false` = redirect when career doesn't match prefix, `true` = redirect when it does
- `overrides` map allows per-career alternative targets (e.g., WP gets `to_1h_hammer_shield_priest` instead of default `to_1h_sword`)
- Standard redirect table (`_anim_redirect`) uses `Unit.has_animation_event` native check for genuinely missing events
- All redirect calls wrapped in `pcall` to prevent crashes from animation mismatches

## [2026-04-24 v0.3.0-dev]
### Fixed
- Removed `we_1h_spears_shield` (Kerillian's Spear & Shield) from Grail Knight — crashes hero previewer due to missing model/animations for Kruber.
- Added `es_deus_01` (Kruber's Spear & Shield) to Grail Knight instead. Note: weapon key is `es_deus_01`, not an obvious name.

### Added
- `/dump` command — dumps all equipped item data (key, item_type, template, rarity, units, can_wield) to console log.
- Cross-character longbow unlocks: `we_longbow` for all 4 Kruber careers, `es_longbow` for all 4 Kerillian careers.
- Cross-character crossbow unlocks: `dr_crossbow` for WHC/BH/Zealot, `wh_crossbow` for all 4 Bardin careers.
- Kerillian's Volley Crossbow (`we_crossbow_repeater`) for all 4 Saltzpyre careers.
- Bardin's Crossbow (`dr_crossbow`) for Engineer and Slayer.
- Bardin's Throwing Axes (`dr_1h_throwing_axes`) for Ironbreaker and Engineer.
- Separated ranged weapon unlocks into dedicated Ranged section in mod settings menu.

## [2026-04-23]
### Changed
- Modularized the project into three separate mods: `weapon_tweaker`, `career_tweaker`, and `chaos_wastes_tweaker`.
- Updated `weapon_tweaker` with the core weapon unlocking and animation logic.

### Fixed
- Fixed a fatal Stingray compiler crash caused by missing `valid_tags` in `lua_preprocessor_defines.config`.
- Improved hook safety in `weapon_tweaker.lua` to prevent engine-level assertion failures when pcall fails.

### Added
- Aggressive debug logging for weapon creation, animation events, and slot wielding in `weapon_tweaker`.
- New `enable_weapon_debug_logging` setting to toggle detailed logs.

## [2026-04-21]
### Fixed
- Fixed `BackendUtils.get_item_units` hook that was causing crashes by incorrectly handling return values.
- Fixed `apply_weapon_unlocks` to correctly restore `can_wield` to `nil` when the original was `nil`.
