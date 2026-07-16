# Open issue empirical contingency register

Generated from the live GitHub issue body, comments, labels, and URL at `2026-07-16T15:56:07.4052738Z`. This is a recovery register, not a root-cause claim. Each path states the evidence that must trigger it and the observation that falsifies it. `Insufficient evidence` entries deliberately request a bounded probe instead of inventing a fix.

Open issues audited: **295**.

## #2 - Split oversized Lua modules and restore CI

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/2](https://github.com/Ensrick/vermintide-2-tweaker/issues/2)
- Current labels: `enhancement, audit, refactor, tooling, verify-fix, 2-moderate`
- Evidence class: `shared_preview_presentation_descriptor, custom_unit_behavioral_contract, asset_alpha_mip_material_contract, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, custom_asset_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #48 - cosmetics_tweaker: per-instance weavebound-glow customizer popup for Evengleam (Bretonian Longsword)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/48](https://github.com/Ensrick/vermintide-2-tweaker/issues/48)
- Current labels: `enhancement, Tweaker: Cosmetics, diagnostics-armed`
- Evidence class: `renderer_specific_material_closure, shared_preview_presentation_descriptor, custom_unit_behavioral_contract, asset_alpha_mip_material_contract, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #52 - ct: gargoyle skull pickups missing on Tower of Treachery (when injected as CW adventure map)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/52](https://github.com/Ensrick/vermintide-2-tweaker/issues/52)
- Current labels: `bug, Tweaker: Chaos Wastes, diagnostics-armed`
- Evidence class: `source_first_engine_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #60 - ct: Belakor shadow locus missing on CW Belakor mission with campaign geometry (Karak Azgaraz "Beacons") — 5 chests of trials spawned when host cap was 3, no altar

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/60](https://github.com/Ensrick/vermintide-2-tweaker/issues/60)
- Current labels: `bug, Tweaker: Chaos Wastes, diagnostics-armed`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #61 - enemy_tweaker: Client-side personal difficulty handicap (self-nerf)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/61](https://github.com/Ensrick/vermintide-2-tweaker/issues/61)
- Current labels: `enhancement, deferred, Tweaker: Enemies, verify-fix-coop`
- Evidence class: `network_peer_parity, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #61 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #63 - ct: optional coin cost for Chests of Trials (deus_cursed_chest)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/63](https://github.com/Ensrick/vermintide-2-tweaker/issues/63)
- Current labels: `enhancement, Tweaker: Chaos Wastes, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #63 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #72 - gt_dev: v0.2.80 lobby-fix hardening backlog (missing regression tests, unknown-popup-result branch, leaving_game guard)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/72](https://github.com/Ensrick/vermintide-2-tweaker/issues/72)
- Current labels: `enhancement, audit, deferred, Tweaker: General, verify-fix`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #80 - cim: make the vanilla HeroView Crafting tab accessible + usable in-mission (root gate is is_in_inn, not menu_access_allowed_in_state)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/80](https://github.com/Ensrick/vermintide-2-tweaker/issues/80)
- Current labels: `enhancement, Tweaker: GUI, cim, cross-mod, verify-fix`
- Evidence class: `renderer_specific_material_closure, shared_preview_presentation_descriptor, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #87 - gut: in-mission gear/customize icon — gate on cim/cosmetics_tweaker; hide in gut-alone; + toggle defaults ON

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/87](https://github.com/Ensrick/vermintide-2-tweaker/issues/87)
- Current labels: `bug, Tweaker: GUI, cim, Tweaker: Cosmetics, cross-mod, verify-fix`
- Evidence class: `canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #102 - ct_dev: multi-use temper (upgrade) altar escalates upgrade rarity to exotic/unique on reuse — visual keep-lit bump leaks into the reward

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/102](https://github.com/Ensrick/vermintide-2-tweaker/issues/102)
- Current labels: `bug, regression, Tweaker: Chaos Wastes, verify-fix`
- Evidence class: `network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #105 - wt + ct: upgrading the elf longbow (worn on Kruber via weapon_tweaker) at a CW upgrade altar reverts it to Kruber's longbow (es_longbow)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/105](https://github.com/Ensrick/vermintide-2-tweaker/issues/105)
- Current labels: `bug, Tweaker: Chaos Wastes, Tweaker: Weapons, cross-mod, diagnostics-armed`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #107 - ct_dev: banned grudge mark appears on Belakor Shadow Lieutenant champion — SL bypasses BossGrudgeMarks; also host/client ban divergence

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/107](https://github.com/Ensrick/vermintide-2-tweaker/issues/107)
- Current labels: `bug, Tweaker: Chaos Wastes, diagnostics-armed, coop-required`
- Evidence class: `asset_alpha_mip_material_contract, network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #108 - wt (dev menu): show 3P anim redirect + model substitute on every Weapon Availability label

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/108](https://github.com/Ensrick/vermintide-2-tweaker/issues/108)
- Current labels: `enhancement, Tweaker: Weapons, verify-fix`
- Evidence class: `custom_asset_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #109 - wt: 3P coverage — KRUBER cross-character weapons

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/109](https://github.com/Ensrick/vermintide-2-tweaker/issues/109)
- Current labels: `enhancement, audit, Tweaker: Weapons, diagnostics-armed`
- Evidence class: `network_peer_parity, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #110 - wt: 3P coverage — BARDIN cross-character weapons

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/110](https://github.com/Ensrick/vermintide-2-tweaker/issues/110)
- Current labels: `enhancement, audit, Tweaker: Weapons, verify-fix`
- Evidence class: `network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #111 - wt: 3P coverage — KERILLIAN cross-character weapons

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/111](https://github.com/Ensrick/vermintide-2-tweaker/issues/111)
- Current labels: `enhancement, audit, Tweaker: Weapons, diagnostics-armed`
- Evidence class: `network_peer_parity, source_first_engine_contract, custom_asset_contract`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #112 - wt: 3P coverage — SALTZPYRE (non-WP) cross-character weapons

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/112](https://github.com/Ensrick/vermintide-2-tweaker/issues/112)
- Current labels: `enhancement, audit, Tweaker: Weapons, verify-fix-coop`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #112 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #113 - wt: 3P coverage — WARRIOR PRIEST cross-character weapons

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/113](https://github.com/Ensrick/vermintide-2-tweaker/issues/113)
- Current labels: `enhancement, audit, Tweaker: Weapons, verify-fix`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #132 - ct_dev: Khazukan Kazakit-ha spawns 5 Chests of Trials despite cursed_chest_count setting (cap not enforced on this mission)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/132](https://github.com/Ensrick/vermintide-2-tweaker/issues/132)
- Current labels: `bug, Tweaker: Chaos Wastes, diagnostics-armed`
- Evidence class: `network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #135 - ct_dev: weekly god override mismatch — set Khorne→Tzeentch, got Slaanesh in-game

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/135](https://github.com/Ensrick/vermintide-2-tweaker/issues/135)
- Current labels: `bug, Tweaker: Chaos Wastes, diagnostics-armed`
- Evidence class: `network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #136 - ct_dev: client sees the WRONG mission (host/client CW mission divergence)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/136](https://github.com/Ensrick/vermintide-2-tweaker/issues/136)
- Current labels: `bug, Tweaker: Chaos Wastes, diagnostics-armed, coop-required`
- Evidence class: `asset_alpha_mip_material_contract, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #138 - wt: Saltzpyre's crossbow missing as a ranged option on Kruber (regressed — worked with Repeating Handgun anims)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/138](https://github.com/Ensrick/vermintide-2-tweaker/issues/138)
- Current labels: `bug, Tweaker: Weapons, verify-fix`
- Evidence class: `source_first_engine_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #139 - gt_dev: bots teleport AWAY FROM* newly-downed player instead of reviving

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/139](https://github.com/Ensrick/vermintide-2-tweaker/issues/139)
- Current labels: `bug, Tweaker: General, 0-critical, verify-fix-coop`
- Evidence class: `custom_unit_behavioral_contract, asset_alpha_mip_material_contract, network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #139 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #141 - ct_dev (feature): save / resume a Chaos Wastes expedition

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/141](https://github.com/Ensrick/vermintide-2-tweaker/issues/141)
- Current labels: `Tweaker: Chaos Wastes, diagnostics-armed, feature`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #142 - gt_dev: bots can't path back up/past a drop-down ledge regardless of bot-distance settings

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/142](https://github.com/Ensrick/vermintide-2-tweaker/issues/142)
- Current labels: `bug, Tweaker: General, verify-fix`
- Evidence class: `custom_unit_behavioral_contract, asset_alpha_mip_material_contract, bounded_transaction_lifecycle, source_first_engine_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #144 - ct_dev: starting boon lost when acquiring another boon (Vaul's Anvil disappeared)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/144](https://github.com/Ensrick/vermintide-2-tweaker/issues/144)
- Current labels: `bug, Tweaker: Chaos Wastes, verify-fix`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #146 - ct_dev (feature): allow a different dominant god on the Citadel of Eternity finale vs the mission

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/146](https://github.com/Ensrick/vermintide-2-tweaker/issues/146)
- Current labels: `Tweaker: Chaos Wastes, verify-fix, feature`
- Evidence class: `network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #148 - [crash] cosmetics_tweaker: loot_item_unit_previewer.lua:142 index _unit_start_position_boxed (nil) — Loremaster preview

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/148](https://github.com/Ensrick/vermintide-2-tweaker/issues/148)
- Current labels: `bug, crash, Tweaker: Cosmetics, verify-fix, 0-critical`
- Evidence class: `shared_preview_presentation_descriptor, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #149 - cosmetics_tweaker: LA Myrmidia Sun shield reverts to default imperial shield on Bret sword & shield at MISSION START (host/client divergence)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/149](https://github.com/Ensrick/vermintide-2-tweaker/issues/149)
- Current labels: `bug, Tweaker: Cosmetics, verify-fix-coop`
- Evidence class: `renderer_specific_material_closure, shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, custom_asset_contract`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #149 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #150 - [crash] cim/cosmetics_tweaker: hero_window_item_customization.lua:2392 index nil; skin hover applies to live model (warped textures); shields buggy

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/150](https://github.com/Ensrick/vermintide-2-tweaker/issues/150)
- Current labels: `bug, crash, cim, verify-fix`
- Evidence class: `shared_preview_presentation_descriptor, custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #153 - Surface hidden career passive perks in the talent menu (e.g. WHC 'Power of Sigmar' +25% headshot, 'Sigmar's Charm' +5% crit)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/153](https://github.com/Ensrick/vermintide-2-tweaker/issues/153)
- Current labels: `enhancement, Tweaker: GUI, Tweaker: Career, verify-fix`
- Evidence class: `network_peer_parity, dynamic_localization_ui_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #154 - cosmetics_tweaker: cross-character WEAPON cosmetics don't render on teammates (husks) — empty husk cache + unit NOT in resource manager (weapon twin of #149)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/154](https://github.com/Ensrick/vermintide-2-tweaker/issues/154)
- Current labels: `bug, Tweaker: Cosmetics, diagnostics-armed, coop-required`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #155 - [crash] gut: cosmetics tab in mission crashes — `gui_pose_items_atlas` not found in Gui (weapon-pose items, borrowed renderer)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/155](https://github.com/Ensrick/vermintide-2-tweaker/issues/155)
- Current labels: `bug, crash, Tweaker: GUI, verify-fix`
- Evidence class: `renderer_specific_material_closure, unsafe_native_call_preflight, network_peer_parity, canonical_identity_persistence, source_first_engine_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #159 - wt: note in-game LOCALIZED names in dev comments wherever internal keys appear; menus use localized names only

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/159](https://github.com/Ensrick/vermintide-2-tweaker/issues/159)
- Current labels: `bug, Tweaker: Weapons, verify-fix`
- Evidence class: `canonical_identity_persistence, bounded_transaction_lifecycle, dynamic_localization_ui_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #161 - wt: polearm regression — Kerillian Spear + Kruber Halberd lost anims on Saltzpyre; add to dev picker + re-fix swing remap

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/161](https://github.com/Ensrick/vermintide-2-tweaker/issues/161)
- Current labels: `bug, Tweaker: Chaos Wastes, verify-fix`
- Evidence class: `source_first_engine_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #167 - gut Mod Tweaker: releasing a slider drag = 3-6 rapid machine-gun click sounds + slider keeps following the cursor after let-go

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/167](https://github.com/Ensrick/vermintide-2-tweaker/issues/167)
- Current labels: `bug, Tweaker: GUI, verify-fix`
- Evidence class: `backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #168 - wt (dev hold-pose tuner): split offset/rotation per-hand (RH + LH groups), remove hand-selector dropdown

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/168](https://github.com/Ensrick/vermintide-2-tweaker/issues/168)
- Current labels: `bug, Tweaker: Weapons, verify-fix`
- Evidence class: `canonical_identity_persistence, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #169 - Cross-mod: replace per-mod `enable_debug_logging` toggles with VMF's built-in logging (output_mode_debug / mod:debug)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/169](https://github.com/Ensrick/vermintide-2-tweaker/issues/169)
- Current labels: `enhancement, cross-mod, verify-fix`
- Evidence class: `canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #172 - gut + cosmetic_tweaker: re-ENABLE the in-mission Cosmetics tab + gear-icon (illusion swap) menu, fully functional (reverses #155 gate)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/172](https://github.com/Ensrick/vermintide-2-tweaker/issues/172)
- Current labels: `enhancement, Tweaker: GUI, Tweaker: Cosmetics, cross-mod, verify-fix`
- Evidence class: `renderer_specific_material_closure, canonical_identity_persistence`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #178 - wt: Rapier (wh_fencing_sword) on Kruber → 1H sword anims + add to dev picker

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/178](https://github.com/Ensrick/vermintide-2-tweaker/issues/178)
- Current labels: `bug, Tweaker: Weapons, verify-fix`
- Evidence class: `general_regression_and_verification_discipline`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #180 - wt: Saltzpyre Greathammer (wh_2h_hammer) bad anims on Kruber — re-add to picker, mark needs-anims

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/180](https://github.com/Ensrick/vermintide-2-tweaker/issues/180)
- Current labels: `bug, Tweaker: Weapons, verify-fix`
- Evidence class: `general_regression_and_verification_discipline`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #181 - wt: Skullsplitter & Tome (wh_hammer_book) on Kruber → 3P model-sub to 1H Skullsplitter + 1H mace anims

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/181](https://github.com/Ensrick/vermintide-2-tweaker/issues/181)
- Current labels: `bug, Tweaker: Weapons, verify-fix`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, custom_asset_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #182 - wt: Cog Hammer (dr_2h_cog_hammer) on Kruber needs anim fix — re-add to dev picker, mark needs-anims

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/182](https://github.com/Ensrick/vermintide-2-tweaker/issues/182)
- Current labels: `bug, Tweaker: Weapons, verify-fix`
- Evidence class: `general_regression_and_verification_discipline`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #183 - wt: Kruber RANGED Weapon Availability — tags, localized names, and source-char ordering all broken

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/183](https://github.com/Ensrick/vermintide-2-tweaker/issues/183)
- Current labels: `bug, Tweaker: Weapons, verify-fix`
- Evidence class: `dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #184 - wt: Kruber RANGED cross-character weapons missing from dev anim picker (needs ranged SETs)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/184](https://github.com/Ensrick/vermintide-2-tweaker/issues/184)
- Current labels: `enhancement, Tweaker: Weapons, diagnostics-armed`
- Evidence class: `backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #196 - wt: Billhook (SET F) charge-attack picks don't play — picker vocab lists 1P anim_event, not 3P anim_event_3p

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/196](https://github.com/Ensrick/vermintide-2-tweaker/issues/196)
- Current labels: `bug, audit, Tweaker: Weapons, verify-fix`
- Evidence class: `source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #200 - cosmetics_tweaker: offhand illusion pick commits to live weapon without Apply + stale offhand texture warps onto mismatched preview mesh (weapon-side sibling of #150)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/200](https://github.com/Ensrick/vermintide-2-tweaker/issues/200)
- Current labels: `bug, verify-fix-coop`
- Evidence class: `renderer_specific_material_closure, shared_preview_presentation_descriptor, asset_alpha_mip_material_contract, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #200 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #203 - cosmetics_tweaker: LA offhand shield illusion DROPS on the local player's own body in-mission (mission-entry + primary<->secondary weapon swap)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/203](https://github.com/Ensrick/vermintide-2-tweaker/issues/203)
- Current labels: `bug, Tweaker: Cosmetics, diagnostics-armed`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #204 - cosmetics_tweaker: Empire Sword and Shield warps LA shield texture onto the wrong (un-swapped) mesh — mesh gate not applied to husk/peer paint (generalize #150 BUG1/2 fix)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/204](https://github.com/Ensrick/vermintide-2-tweaker/issues/204)
- Current labels: `bug, Tweaker: Cosmetics, verify-fix-coop`
- Evidence class: `asset_alpha_mip_material_contract, network_peer_parity, canonical_identity_persistence, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #204 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #205 - ct_dev: host settings-sync floods reliable send queue → HOST CRASH when rapidly editing settings (gut Mod Tweaker) in CW keep

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/205](https://github.com/Ensrick/vermintide-2-tweaker/issues/205)
- Current labels: `bug, crash, Tweaker: Chaos Wastes, verify-fix-coop`
- Evidence class: `custom_unit_behavioral_contract, appearance_surface_fanout, network_peer_parity, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #205 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #209 - gut 3rd-person camera: screen/camera effects use FIRST-person variants instead of third-person

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/209](https://github.com/Ensrick/vermintide-2-tweaker/issues/209)
- Current labels: `bug, Tweaker: GUI, verify-fix`
- Evidence class: `custom_unit_behavioral_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #218 - wt: remove dead _strip_cim_widgets scaffolding (cw_melee_traits / cw_ranged_traits groups no longer exist)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/218](https://github.com/Ensrick/vermintide-2-tweaker/issues/218)
- Current labels: `enhancement, refactor, verify-fix`
- Evidence class: `network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #219 - Cross-mod: orphan localization key cleanup (found by 2026-07-01 menu-reorg audit)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/219](https://github.com/Ensrick/vermintide-2-tweaker/issues/219)
- Current labels: `enhancement, audit, cross-mod, verify-fix`
- Evidence class: `network_peer_parity, canonical_identity_persistence, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #221 - Menu consolidation phase 2: umbrella MASTER toggles (needs code gating) - MENU_CONSOLIDATION_PLAN sections 2-4

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/221](https://github.com/Ensrick/vermintide-2-tweaker/issues/221)
- Current labels: `enhancement, deferred, cross-mod, not-started`
- Evidence class: `network_peer_parity, backend_realm_isolation`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #222 - Loc sweep follow-up: option descriptions repeat the title already shown as the popup's orange header (all mods)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/222](https://github.com/Ensrick/vermintide-2-tweaker/issues/222)
- Current labels: `bug, Tweaker: Career, cross-mod, not-started`
- Evidence class: `network_peer_parity, canonical_identity_persistence, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #224 - gut_dev compendium (#217): Armory/Bestiary tab labels + entries render <key> angle-bracket markers (global Localize cannot see VMF loc keys)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/224](https://github.com/Ensrick/vermintide-2-tweaker/issues/224)
- Current labels: `bug, audit, Tweaker: GUI, verify-fix`
- Evidence class: `source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #226 - cwv/cim: CIM-crafted "Old Musket" is deprecated variant (key=cwv_es_musket_old, rarity=modded, skin=nil) — not the exotic es_handgun+skin form the mod auto-grants

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/226](https://github.com/Ensrick/vermintide-2-tweaker/issues/226)
- Current labels: `bug, cim, CWV, verify-fix`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, custom_asset_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #227 - cwv: "Old Musket" illusion blinks red/transparent in cosmetic menu — skin has no matching_item_key

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/227](https://github.com/Ensrick/vermintide-2-tweaker/issues/227)
- Current labels: `bug, CWV, verify-fix`
- Evidence class: `canonical_identity_persistence, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #228 - [crash] Native AV in ShadingEnvironment.blend (world render) ~1s after shield-skin preview load in HeroWindowItemCustomization (keep forge/cosmetics)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/228](https://github.com/Ensrick/vermintide-2-tweaker/issues/228)
- Current labels: `bug, crash, Tweaker: Cosmetics, verify-fix`
- Evidence class: `unsafe_native_call_preflight, shared_preview_presentation_descriptor, custom_unit_behavioral_contract, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #231 - gut: expand native loadout slots beyond 6 (target 30) - custom roman-numeral icons + selection-bar GUI for >6

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/231](https://github.com/Ensrick/vermintide-2-tweaker/issues/231)
- Current labels: `enhancement, Tweaker: GUI, diagnostics-armed`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #232 - gut: fix vanilla bug - bots don't use the designated bot-loadout victory pose (player_bot.lua:142 drops is_bot)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/232](https://github.com/Ensrick/vermintide-2-tweaker/issues/232)
- Current labels: `bug, Tweaker: GUI, verify-fix`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #237 - cwv: elf Sword & Shield (cwv_we_sword_shield) renders as Kruber's sword+shield on the inventory character-preview model

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/237](https://github.com/Ensrick/vermintide-2-tweaker/issues/237)
- Current labels: `bug, CWV, verify-fix`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #241 - gt noclip: ledge-grab / out-of-bounds triggers still fire while noclipping

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/241](https://github.com/Ensrick/vermintide-2-tweaker/issues/241)
- Current labels: `bug, Tweaker: General, 1-major, verify-fix-coop`
- Evidence class: `custom_unit_behavioral_contract, appearance_surface_fanout, network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #241 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #242 - gt disable enemy spawns: monsters and patrols still spawn

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/242](https://github.com/Ensrick/vermintide-2-tweaker/issues/242)
- Current labels: `bug, Tweaker: General, verify-fix`
- Evidence class: `source_first_engine_contract, dynamic_localization_ui_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #243 - ct_dev: Belakor curse lighting too dark on already-dark interior injected maps (Devious Delvings / dlc_termite_2)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/243](https://github.com/Ensrick/vermintide-2-tweaker/issues/243)
- Current labels: `bug, Tweaker: Chaos Wastes, verify-fix`
- Evidence class: `asset_alpha_mip_material_contract, network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #244 - cim: Athanor-forged property values display adventure-range-scaled numbers instead of the forged value

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/244](https://github.com/Ensrick/vermintide-2-tweaker/issues/244)
- Current labels: `bug, cim, verify-fix`
- Evidence class: `general_regression_and_verification_discipline`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #245 - Hold-Tab weapon preview: displayed properties don't refresh after weapon properties are changed

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/245](https://github.com/Ensrick/vermintide-2-tweaker/issues/245)
- Current labels: `bug, verify-fix`
- Evidence class: `renderer_specific_material_closure, shared_preview_presentation_descriptor, network_peer_parity, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #246 - [vanilla] Hold-Tab player weapon preview shows wrong weapon cosmetic (illusion) icon

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/246](https://github.com/Ensrick/vermintide-2-tweaker/issues/246)
- Current labels: `bug, cim, 2-moderate, verify-fix-coop`
- Evidence class: `renderer_specific_material_closure, shared_preview_presentation_descriptor, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, custom_asset_contract, dynamic_localization_ui_contract`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #246 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #247 - gt: get bot takeover options working

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/247](https://github.com/Ensrick/vermintide-2-tweaker/issues/247)
- Current labels: `bug, Tweaker: General, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #247 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #249 - ct: 'more ammo per boon' — client HUD ammo count desyncs (shows 36 when actual is 62)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/249](https://github.com/Ensrick/vermintide-2-tweaker/issues/249)
- Current labels: `bug, Tweaker: Chaos Wastes, diagnostics-armed, 2-moderate, coop-required`
- Evidence class: `appearance_surface_fanout, network_peer_parity, source_first_engine_contract`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #250 - [vanilla] Hold-Tab talent preview is corrupted when talents are granted as Chaos Wastes boons

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/250](https://github.com/Ensrick/vermintide-2-tweaker/issues/250)
- Current labels: `bug, verify-fix`
- Evidence class: `shared_preview_presentation_descriptor, network_peer_parity, canonical_identity_persistence`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #251 - ct: chest fails to spawn at the first-tome location on Blood in the Darkness

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/251](https://github.com/Ensrick/vermintide-2-tweaker/issues/251)
- Current labels: `bug, Tweaker: Chaos Wastes, diagnostics-armed, 2-moderate`
- Evidence class: `network_peer_parity, canonical_identity_persistence`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #252 - ct: multi-use temper altar shows red 'same rarity' message on reroll use — should message that it rerolls traits/properties

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/252](https://github.com/Ensrick/vermintide-2-tweaker/issues/252)
- Current labels: `bug, Tweaker: Chaos Wastes, verify-fix, 3-low`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, dynamic_localization_ui_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #253 - [idea] ct: expose Weave (Winds of Magic) modifiers as Chaos Wastes curses

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/253](https://github.com/Ensrick/vermintide-2-tweaker/issues/253)
- Current labels: `Tweaker: Chaos Wastes, diagnostics-armed, feature, 3-low`
- Evidence class: `canonical_identity_persistence, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #254 - gt: creature spawner does nothing in Chaos Wastes missions

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/254](https://github.com/Ensrick/vermintide-2-tweaker/issues/254)
- Current labels: `bug, Tweaker: General, Tweaker: Chaos Wastes, verify-fix, 2-moderate`
- Evidence class: `custom_unit_behavioral_contract, source_first_engine_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #256 - ct: 'ammo per boon' boon can result in NEGATIVE ammo

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/256](https://github.com/Ensrick/vermintide-2-tweaker/issues/256)
- Current labels: `bug, Tweaker: Chaos Wastes, verify-fix, 1-major`
- Evidence class: `network_peer_parity`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #257 - Trace Well of Dreams Fade

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/257](https://github.com/Ensrick/vermintide-2-tweaker/issues/257)
- Current labels: `bug, Tweaker: GUI, diagnostics-armed, 2-moderate`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, source_first_engine_contract`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #258 - ct: 'Well of Dreams' too dark under Tzeentch curse lighting — lighten amb_top by 100%

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/258](https://github.com/Ensrick/vermintide-2-tweaker/issues/258)
- Current labels: `bug, Tweaker: Chaos Wastes, verify-fix, 1-major`
- Evidence class: `asset_alpha_mip_material_contract, canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #259 - ct: Morgrim's Bomb not consumed with Ranger Vet 'bomb re-use on ability' talent + CT toggle active

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/259](https://github.com/Ensrick/vermintide-2-tweaker/issues/259)
- Current labels: `bug, Tweaker: Chaos Wastes, verify-fix, 2-moderate`
- Evidence class: `canonical_identity_persistence`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #263 - cim: modded-rarity upgrade button in illusion/cosmetic viewer has no text

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/263](https://github.com/Ensrick/vermintide-2-tweaker/issues/263)
- Current labels: `enhancement, cim, verify-fix, 2-moderate`
- Evidence class: `network_peer_parity`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #266 - cosmetics/LA: availability parity - every LA shield illusion must be offered on ALL of Kruber's shield weapons, and every fix must apply weapon-agnostically

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/266](https://github.com/Ensrick/vermintide-2-tweaker/issues/266)
- Current labels: `enhancement, Tweaker: Cosmetics, 2-moderate, verify-fix-coop`
- Evidence class: `shared_preview_presentation_descriptor, custom_unit_behavioral_contract, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #266 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #269 - wt: holstered staff on a Kruber ranged slot may not render on hip (a_unwielded_staff node; guard drops link, no crash)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/269](https://github.com/Ensrick/vermintide-2-tweaker/issues/269)
- Current labels: `bug, Tweaker: Weapons, verify-fix, 2-moderate`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, bounded_transaction_lifecycle, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #271 - ct: Devious Delvings curse lighting needs to be ~2x brighter

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/271](https://github.com/Ensrick/vermintide-2-tweaker/issues/271)
- Current labels: `bug, Tweaker: Chaos Wastes, verify-fix, 1-major`
- Evidence class: `asset_alpha_mip_material_contract, canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #272 - [idea] gut: incorporate Scoreboard mod features (detailed end-round + in-game Tab stats)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/272](https://github.com/Ensrick/vermintide-2-tweaker/issues/272)
- Current labels: `Tweaker: GUI, feature, 2-moderate, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #272 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #273 - cwv/ct: CWV weapons collapse to career defaults during Chaos Wastes conversion

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/273](https://github.com/Ensrick/vermintide-2-tweaker/issues/273)
- Current labels: `bug, Tweaker: Chaos Wastes, CWV, cross-mod, 1-major, verify-fix-coop`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #273 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #274 - gut: end-of-mission cutscene on dlc_dwarf_whaling (Parting of the Waves) - no cutscene plays, camera locks on map geometry and stalls for the cutscene duration

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/274](https://github.com/Ensrick/vermintide-2-tweaker/issues/274)
- Current labels: `bug, Tweaker: GUI, verify-fix, 3-low`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #277 - cim: add a way to delete all modded weapons (bulk cleanup)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/277](https://github.com/Ensrick/vermintide-2-tweaker/issues/277)
- Current labels: `enhancement, cim, 3-low, not-started`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #278 - cwv/cim: crafted CWV ranged item CTDs a client on loadout sync — NetworkLookup item_names missing key (rpc_sync_loadout_slot)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/278](https://github.com/Ensrick/vermintide-2-tweaker/issues/278)
- Current labels: `bug, crash, cim, CWV, cross-mod, 0-critical, verify-fix-coop`
- Evidence class: `appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #278 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #279 - cwv/cim: crafted CWV item renders a MERGED model (source weapon mesh bleeds into the CWV template) — e.g. outrider grenade launcher + trollhammer

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/279](https://github.com/Ensrick/vermintide-2-tweaker/issues/279)
- Current labels: `bug, cim, CWV, cross-mod, diagnostics-armed, 0-critical, coop-required`
- Evidence class: `appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, custom_asset_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #281 - gut_dev: hb/hb_data.lua:44 aborts at load - module 'pl.import_into' not found (Penlight dep missing)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/281](https://github.com/Ensrick/vermintide-2-tweaker/issues/281)
- Current labels: `bug, Tweaker: GUI, verify-fix, 2-moderate`
- Evidence class: `network_peer_parity, source_first_engine_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #283 - crt: 'Job Well Done' stacks reset just from opening the talent menu mid-mission (should only reset on an actual talent change)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/283](https://github.com/Ensrick/vermintide-2-tweaker/issues/283)
- Current labels: `bug, Tweaker: Career, 2-moderate, not-started`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #285 - gut_dev: respawn timer over death portrait renders nothing - port approach from working mod 复活CD/Respawn CD (3747644100)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/285](https://github.com/Ensrick/vermintide-2-tweaker/issues/285)
- Current labels: `bug, Tweaker: GUI, verify-fix, 1-major`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, custom_asset_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #287 - gut: can't change cosmetics in modded realm when 'Use non-modded loadouts' (gut_use_non_modded_loadouts) is ON

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/287](https://github.com/Ensrick/vermintide-2-tweaker/issues/287)
- Current labels: `bug, Tweaker: GUI, Tweaker: Cosmetics, cross-mod, 2-moderate, verify-fix-coop`
- Evidence class: `appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #287 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #288 - ct: Anath Raema's Swiftness permanent-reload rework (tweak_anath_raema_permanent) fails to apply

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/288](https://github.com/Ensrick/vermintide-2-tweaker/issues/288)
- Current labels: `bug, Tweaker: Chaos Wastes, verify-fix, 2-moderate`
- Evidence class: `asset_alpha_mip_material_contract, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, dynamic_localization_ui_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #289 - [idea] ct: allow more Chaos Wastes modifiers active at once + a progressive-difficulty ramp option

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/289](https://github.com/Ensrick/vermintide-2-tweaker/issues/289)
- Current labels: `enhancement, Tweaker: Chaos Wastes, diagnostics-armed, 3-low, coop-required`
- Evidence class: `network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #290 - wt: v0.12.201 dropped ~30 Kruber/Saltzpyre 3P picks (only Kerillian baked) — polearms T-pose on Kruber

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/290](https://github.com/Ensrick/vermintide-2-tweaker/issues/290)
- Current labels: `bug, regression, Tweaker: Weapons, verify-fix, 1-major`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #292 - Save and swap native graphics profiles

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/292](https://github.com/Ensrick/vermintide-2-tweaker/issues/292)
- Current labels: `enhancement, Tweaker: GUI, verify-fix, 2-moderate`
- Evidence class: `unsafe_native_call_preflight, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #296 - Tuskgor Javelins cannot recover after impact

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/296](https://github.com/Ensrick/vermintide-2-tweaker/issues/296)
- Current labels: `bug, CWV, 2-moderate, verify-fix-coop`
- Evidence class: `network_peer_parity`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #296 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #298 - Bot Combat Improvement Options

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/298](https://github.com/Ensrick/vermintide-2-tweaker/issues/298)
- Current labels: `Tweaker: General, verify-fix, feature, 2-moderate`
- Evidence class: `network_peer_parity, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #299 - Chest of Trials Revive Teleport Fail

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/299](https://github.com/Ensrick/vermintide-2-tweaker/issues/299)
- Current labels: `bug, Tweaker: Chaos Wastes, 1-major, verify-fix-coop`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #299 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #300 - gt_bot_rescue_awaiting

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/300](https://github.com/Ensrick/vermintide-2-tweaker/issues/300)
- Current labels: `bug, Tweaker: General, verify-fix, 2-moderate`
- Evidence class: `network_peer_parity, source_first_engine_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #302 - Debug highlight options for

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/302](https://github.com/Ensrick/vermintide-2-tweaker/issues/302)
- Current labels: `Tweaker: General, tooling, verify-fix, feature, 1-major`
- Evidence class: `custom_unit_behavioral_contract, asset_alpha_mip_material_contract, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, custom_asset_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #303 - Freeze AI

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/303](https://github.com/Ensrick/vermintide-2-tweaker/issues/303)
- Current labels: `Tweaker: General, tooling, verify-fix, feature, 1-major`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #309 - Protect players during transient disconnects

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/309](https://github.com/Ensrick/vermintide-2-tweaker/issues/309)
- Current labels: `Tweaker: General, diagnostics-armed, feature, 2-moderate, coop-required`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #310 - HUD adjustment mode

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/310](https://github.com/Ensrick/vermintide-2-tweaker/issues/310)
- Current labels: `Tweaker: GUI, diagnostics-armed, feature, 1-major`
- Evidence class: `renderer_specific_material_closure, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #311 - Crosshair Kill Confirmation

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/311](https://github.com/Ensrick/vermintide-2-tweaker/issues/311)
- Current labels: `Tweaker: GUI, verify-fix, feature, 1-major`
- Evidence class: `network_peer_parity`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #312 - UI Tweaks integration

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/312](https://github.com/Ensrick/vermintide-2-tweaker/issues/312)
- Current labels: `Tweaker: GUI, cross-mod, verify-fix, feature, 1-major`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #313 - Integrate Crosshair Kill Confirmation mod options into GUT and the normal Options menu.

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/313](https://github.com/Ensrick/vermintide-2-tweaker/issues/313)
- Current labels: `Tweaker: GUI, feature, 1-major, not-started`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #314 - Hook and modify the mod: "Simple UI (Abandoned)"

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/314](https://github.com/Ensrick/vermintide-2-tweaker/issues/314)
- Current labels: `Tweaker: GUI, verify-fix, feature, 3-low`
- Evidence class: `renderer_specific_material_closure, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #316 - Kruber Longbow draw animation missing on non-Huntsman careers

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/316](https://github.com/Ensrick/vermintide-2-tweaker/issues/316)
- Current labels: `bug, Tweaker: Weapons, 3-low, verify-fix-coop`
- Evidence class: `appearance_surface_fanout, network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #316 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #317 - CWV Animation Picker

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/317](https://github.com/Ensrick/vermintide-2-tweaker/issues/317)
- Current labels: `CWV, tooling, feature, 2-moderate, verify-fix-coop`
- Evidence class: `appearance_surface_fanout, network_peer_parity, canonical_identity_persistence`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #317 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #318 - CWV shows up as a menu tab blacked out when disabled in VMF

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/318](https://github.com/Ensrick/vermintide-2-tweaker/issues/318)
- Current labels: `bug, Tweaker: GUI, CWV, verify-fix, 2-moderate`
- Evidence class: `network_peer_parity, canonical_identity_persistence`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #321 - BR toggles inert across consumers since bt retirement (wt/ct/et/crt): decide reactivation or removal

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/321](https://github.com/Ensrick/vermintide-2-tweaker/issues/321)
- Current labels: `enhancement, cross-mod, verify-fix, 2-moderate`
- Evidence class: `asset_alpha_mip_material_contract, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #322 - [bug] ct: _spawn_pickup hook drops vanilla's 2nd return (pickup_unit_go_id) — breaks linked-pickup client sync

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/322](https://github.com/Ensrick/vermintide-2-tweaker/issues/322)
- Current labels: `bug, Tweaker: Chaos Wastes, 2-moderate, verify-fix-coop`
- Evidence class: `asset_alpha_mip_material_contract, network_peer_parity, source_first_engine_contract`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #322 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #323 - New difficulty feature

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/323](https://github.com/Ensrick/vermintide-2-tweaker/issues/323)
- Current labels: `Tweaker: Chaos Wastes, diagnostics-armed, feature, 3-low, Tweaker: Enemies, coop-required`
- Evidence class: `network_peer_parity, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #324 - Skarrik as a monster

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/324](https://github.com/Ensrick/vermintide-2-tweaker/issues/324)
- Current labels: `enhancement, blocked, Tweaker: Chaos Wastes, diagnostics-armed, 2-moderate`
- Evidence class: `network_peer_parity, dynamic_localization_ui_contract`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #331 - [Chaos Wastes Tweaker] Create Bots Category

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/331](https://github.com/Ensrick/vermintide-2-tweaker/issues/331)
- Current labels: `Tweaker: Chaos Wastes, verify-fix, feature, 2-moderate`
- Evidence class: `general_regression_and_verification_discipline`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #332 - gt: make Visuals & Audio 'Disable mutator death explosions' + 'Max Ragdolls' work client-side (currently host-only)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/332](https://github.com/Ensrick/vermintide-2-tweaker/issues/332)
- Current labels: `enhancement, Tweaker: General, 2-moderate, verify-fix-coop`
- Evidence class: `network_peer_parity, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #332 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #333 - gt: offline Twitch mode + options for which Twitch vote events are allowed to trigger

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/333](https://github.com/Ensrick/vermintide-2-tweaker/issues/333)
- Current labels: `Tweaker: General, feature, 2-moderate, verify-fix-coop`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #333 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #335 - Loc status tags: #301 retro-audit presumed ~800 never-confirmed features [working]; re-derive from evidence

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/335](https://github.com/Ensrick/vermintide-2-tweaker/issues/335)
- Current labels: `bug, diagnostics-armed, 1-major`
- Evidence class: `network_peer_parity, canonical_identity_persistence, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #340 - "Support All Languages" - Fix Square Blocks Player Names/Chat Regardless of Language

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/340](https://github.com/Ensrick/vermintide-2-tweaker/issues/340)
- Current labels: `Tweaker: GUI, diagnostics-armed, feature, 1-major`
- Evidence class: `renderer_specific_material_closure, network_peer_parity, source_first_engine_contract`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #341 - Add a Weapon Tweak toggle for bolt staff

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/341](https://github.com/Ensrick/vermintide-2-tweaker/issues/341)
- Current labels: `Tweaker: Weapons, verify-fix, feature, 2-moderate`
- Evidence class: `canonical_identity_persistence, source_first_engine_contract, dynamic_localization_ui_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #342 - ct_dev: parry-proc cooldown strip is a latent no-op - caller resolves a nil global (since ~v0.7.128)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/342](https://github.com/Ensrick/vermintide-2-tweaker/issues/342)
- Current labels: `bug, Tweaker: Chaos Wastes, verify-fix, 2-moderate`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #343 - [CWV] New Throwable - Smoke Bomb

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/343](https://github.com/Ensrick/vermintide-2-tweaker/issues/343)
- Current labels: `CWV, diagnostics-armed, feature, 3-low`
- Evidence class: `general_regression_and_verification_discipline`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #345 - Loc status tags out of sync with issue state: 16 options (closed-issue stale + missing [verify-fix]) across ct_dev/gt_dev/gut_dev

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/345](https://github.com/Ensrick/vermintide-2-tweaker/issues/345)
- Current labels: `enhancement, audit, Tweaker: GUI, Tweaker: General, Tweaker: Chaos Wastes, cross-mod, verify-fix, 2-moderate`
- Evidence class: `network_peer_parity, canonical_identity_persistence, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #347 - Let Bots Collect Closed-Chest Items

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/347](https://github.com/Ensrick/vermintide-2-tweaker/issues/347)
- Current labels: `Tweaker: General, diagnostics-armed, feature, 2-moderate`
- Evidence class: `network_peer_parity, canonical_identity_persistence, custom_asset_contract`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #348 - Revert Patch 6.11.0 Change to 1-handed Kruber/Sienna Sword

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/348](https://github.com/Ensrick/vermintide-2-tweaker/issues/348)
- Current labels: `Tweaker: Weapons, verify-fix, feature, 1-major`
- Evidence class: `network_peer_parity, canonical_identity_persistence`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #349 - [CT] Mission of Mercy - Investigate Possible Overflow of Chests of Trials

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/349](https://github.com/Ensrick/vermintide-2-tweaker/issues/349)
- Current labels: `bug, Tweaker: Chaos Wastes, diagnostics-armed, 2-moderate`
- Evidence class: `network_peer_parity, source_first_engine_contract`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #350 - Auto-Open Trial Chests at Start

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/350](https://github.com/Ensrick/vermintide-2-tweaker/issues/350)
- Current labels: `Tweaker: Chaos Wastes, feature, 3-low, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #350 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #351 - [CT] Bug Fix - Ravaged Art & Loot Die Not Converting to Pilgrims Coins on Adventure Maps in Chaos Wastes

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/351](https://github.com/Ensrick/vermintide-2-tweaker/issues/351)
- Current labels: `bug, Tweaker: Chaos Wastes, 2-moderate, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #351 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #353 - gut: LA (Loremaster's Armoury) cosmetics equipped at game exit aren't saved into the loadout system

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/353](https://github.com/Ensrick/vermintide-2-tweaker/issues/353)
- Current labels: `bug, Tweaker: GUI, cross-mod, verify-fix, 2-moderate`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #354 - gut: WT cross-character weapon (Tuskgor Spear on Kerillian) not saved to active loadout on exit - intermittent (usually persists)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/354](https://github.com/Ensrick/vermintide-2-tweaker/issues/354)
- Current labels: `bug, Tweaker: GUI, Tweaker: Weapons, cross-mod, diagnostics-armed, 2-moderate`
- Evidence class: `canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #355 - New Commands to Cause Player to be in Downed State or Die

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/355](https://github.com/Ensrick/vermintide-2-tweaker/issues/355)
- Current labels: `Tweaker: General, tooling, verify-fix, feature, 1-major`
- Evidence class: `network_peer_parity, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #356 - [crash] ct_dev: no_roamers pairs(nil) at mission load on Belakor / deus missions (adventure-derived conflict directors)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/356](https://github.com/Ensrick/vermintide-2-tweaker/issues/356)
- Current labels: `bug, crash, blocked, Tweaker: Chaos Wastes, verify-fix`
- Evidence class: `network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #357 - ct: show a buff-bar cooldown timer for the bomb-bubble boon (bomb_boon_cooldown)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/357](https://github.com/Ensrick/vermintide-2-tweaker/issues/357)
- Current labels: `enhancement, Tweaker: Chaos Wastes, 3-low, verify-fix-coop`
- Evidence class: `network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #357 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #358 - ct: show a buff-bar cooldown timer + icon for Manann's Tempest (tweak_manann_tempest_cooldown)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/358](https://github.com/Ensrick/vermintide-2-tweaker/issues/358)
- Current labels: `enhancement, Tweaker: Chaos Wastes, 3-low, verify-fix-coop`
- Evidence class: `renderer_specific_material_closure, network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #358 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #359 - Add Command Wheel From Versus as a Means to Assign (Temporary) Bot Behavior During a Mission

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/359](https://github.com/Ensrick/vermintide-2-tweaker/issues/359)
- Current labels: `Tweaker: GUI, Tweaker: General, verify-fix, feature, 3-low`
- Evidence class: `network_peer_parity`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #361 - Modification of Miasma curse

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/361](https://github.com/Ensrick/vermintide-2-tweaker/issues/361)
- Current labels: `Tweaker: Chaos Wastes, feature, 3-low, verify-fix-coop`
- Evidence class: `network_peer_parity`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #361 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #364 - [gt] Bots auto-pickup Bardin's Ranger Veteran ale and waste it (grabbed + consumed with no benefit / vanishes for the team)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/364](https://github.com/Ensrick/vermintide-2-tweaker/issues/364)
- Current labels: `bug, Tweaker: General, verify-fix, 2-moderate`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #365 - [gt] Smart bot ale auto-consume: only drink Bardin's ale when the whole team is already at 3 stacks with >50% time left

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/365](https://github.com/Ensrick/vermintide-2-tweaker/issues/365)
- Current labels: `Tweaker: General, verify-fix, feature, 3-low`
- Evidence class: `network_peer_parity, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #366 - [crt] Bardin ale buff should decay one stack at a time instead of dropping all 3 at once

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/366](https://github.com/Ensrick/vermintide-2-tweaker/issues/366)
- Current labels: `enhancement, Tweaker: Career, verify-fix, 3-low`
- Evidence class: `dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #367 - [crt] Speed up Bardin's ale-drinking animation

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/367](https://github.com/Ensrick/vermintide-2-tweaker/issues/367)
- Current labels: `enhancement, Tweaker: Career, verify-fix, 3-low`
- Evidence class: `backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #368 - wt/cwv: make weapon availability independent; wt as the control surface (drop cwv_managed cede + fix wh_1h_axe clobber)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/368](https://github.com/Ensrick/vermintide-2-tweaker/issues/368)
- Current labels: `bug, Tweaker: Weapons, CWV, verify-fix, 2-moderate`
- Evidence class: `canonical_identity_persistence, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #369 - [enemy_tweaker] Per-difficulty enemy health multiplier sliders

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/369](https://github.com/Ensrick/vermintide-2-tweaker/issues/369)
- Current labels: `feature, 2-moderate, Tweaker: Enemies, verify-fix-coop`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #369 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #371 - [cross-mod] Auto-disable network-unsafe features when a lobby peer lacks the mod + grey them out in the gut Mod Tweaker with a 'who's missing it' popup

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/371](https://github.com/Ensrick/vermintide-2-tweaker/issues/371)
- Current labels: `Tweaker: GUI, Tweaker: General, cim, CWV, cross-mod, feature, 1-major, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #371 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #373 - cosmetics/LA: LA shield illusion change doesn't apply on the WEAVEBOUND Bretonnian shield (Imperial weavebound works) — weave _magic item_types missing from the shield-family map

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/373](https://github.com/Ensrick/vermintide-2-tweaker/issues/373)
- Current labels: `bug, Tweaker: Cosmetics, 2-moderate, verify-fix-coop`
- Evidence class: `shared_preview_presentation_descriptor, asset_alpha_mip_material_contract, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #373 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #374 - Moonfire bow does not regenerate on non-elf / cross-character careers (energy recharge keyed by career_name)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/374](https://github.com/Ensrick/vermintide-2-tweaker/issues/374)
- Current labels: `bug, CWV, verify-fix, 2-moderate`
- Evidence class: `network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #376 - cosmetics/LA: full illusion persistence + per-instance inventory icons

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/376](https://github.com/Ensrick/vermintide-2-tweaker/issues/376)
- Current labels: `enhancement, Tweaker: Cosmetics, verify-fix, 2-moderate`
- Evidence class: `renderer_specific_material_closure, shared_preview_presentation_descriptor, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #377 - Glow menu auto-open needs in-view toggle button

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/377](https://github.com/Ensrick/vermintide-2-tweaker/issues/377)
- Current labels: `bug, regression, Tweaker: Cosmetics, verify-fix, 1-major`
- Evidence class: `renderer_specific_material_closure, network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #378 - Missing-mod lobby join hangs; no reveal popup

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/378](https://github.com/Ensrick/vermintide-2-tweaker/issues/378)
- Current labels: `bug, Tweaker: General, 1-major, verify-fix-coop`
- Evidence class: `network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #378 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #380 - Downed/bleeding red overlay ignores disable-downed-fx toggle

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/380](https://github.com/Ensrick/vermintide-2-tweaker/issues/380)
- Current labels: `bug, Tweaker: General, diagnostics-armed, 2-moderate`
- Evidence class: `canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #384 - Aid-errand teleport gap when need_type flickers

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/384](https://github.com/Ensrick/vermintide-2-tweaker/issues/384)
- Current labels: `bug, Tweaker: General, 1-major, verify-fix-coop`
- Evidence class: `network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #384 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #385 - Unknown-trigger teleport loop below leash distance

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/385](https://github.com/Ensrick/vermintide-2-tweaker/issues/385)
- Current labels: `bug, Tweaker: General, verify-fix, 2-moderate`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, bounded_transaction_lifecycle`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #388 - Cross-career energy weapons lose heat-bar fx/sound/color

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/388](https://github.com/Ensrick/vermintide-2-tweaker/issues/388)
- Current labels: `bug, Tweaker: Weapons, 2-moderate, verify-fix-coop`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, bounded_transaction_lifecycle`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #388 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #389 - Weapon power slider not stepping by 25 (gut)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/389](https://github.com/Ensrick/vermintide-2-tweaker/issues/389)
- Current labels: `bug, Tweaker: GUI, verify-fix, 2-moderate`
- Evidence class: `backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #391 - WT: per-career availability control surface for CWV

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/391](https://github.com/Ensrick/vermintide-2-tweaker/issues/391)
- Current labels: `Tweaker: Weapons, CWV, verify-fix, feature, 2-moderate`
- Evidence class: `backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #393 - event_tweaker: injected high_intensity mutator has little observable effect

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/393](https://github.com/Ensrick/vermintide-2-tweaker/issues/393)
- Current labels: `bug, diagnostics-armed, 1-major, Tweaker: Events`
- Evidence class: `network_peer_parity, source_first_engine_contract`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #394 - CWV grip offsets not applied on husk (client) view

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/394](https://github.com/Ensrick/vermintide-2-tweaker/issues/394)
- Current labels: `bug, CWV, 2-moderate, verify-fix-coop`
- Evidence class: `appearance_surface_fanout, network_peer_parity, source_first_engine_contract`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #394 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #395 - CWV rapier not unequipped on client after swap

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/395](https://github.com/Ensrick/vermintide-2-tweaker/issues/395)
- Current labels: `bug, CWV, diagnostics-armed, 2-moderate, coop-required`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #396 - CWV Imperial Longsword invisible on client husk view

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/396](https://github.com/Ensrick/vermintide-2-tweaker/issues/396)
- Current labels: `bug, CWV, 2-moderate, verify-fix-coop`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, custom_asset_contract, dynamic_localization_ui_contract`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #396 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #398 - CWV weapon sounds not applied on husk view

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/398](https://github.com/Ensrick/vermintide-2-tweaker/issues/398)
- Current labels: `bug, CWV, 2-moderate, verify-fix-coop`
- Evidence class: `appearance_surface_fanout, network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #398 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #399 - Outrider Grenade Launcher shows Trollhammer torpedo on husk

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/399](https://github.com/Ensrick/vermintide-2-tweaker/issues/399)
- Current labels: `bug, CWV, diagnostics-armed, 2-moderate, coop-required`
- Evidence class: `network_peer_parity, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #400 - Flamestorm staff 3P flame misaligned on cross-career

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/400](https://github.com/Ensrick/vermintide-2-tweaker/issues/400)
- Current labels: `bug, Tweaker: Weapons, 2-moderate, verify-fix-coop`
- Evidence class: `network_peer_parity, source_first_engine_contract`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #400 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #401 - Imperial Axe+Shield reverts to dwarf base model

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/401](https://github.com/Ensrick/vermintide-2-tweaker/issues/401)
- Current labels: `bug, CWV, 2-moderate, verify-fix-coop`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #401 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #402 - gut: modded loadouts + frame leak into official realm

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/402](https://github.com/Ensrick/vermintide-2-tweaker/issues/402)
- Current labels: `bug, regression, Tweaker: GUI, 0-critical, Fixed`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: post-fix hardening, regression coverage, then close

**Fallback 1**

- **Evidence/trigger:** The documented closure test fails on the current named build.
- **Change:** Repair the first regressed invariant covered by the existing issue regression.
- **Falsifier:** The current closure test passes; close the stale issue instead.

**Fallback 2**

- **Evidence/trigger:** The symptom returns after a known-good version.
- **Change:** Bisect the documented introduction/fix range and patch the first regressing commit.
- **Falsifier:** No commit in that range changes the failing path.

**Fallback 3**

- **Evidence/trigger:** The current repair cannot be made safe on the present tree.
- **Change:** Roll back the isolated issue fix and restore the last user-verified vanilla/mod behavior while preparing a current-tree repair.
- **Falsifier:** The fix cannot be isolated without removing unrelated verified work.

## #404 - cim: Athanor renders broken - empty trait picker + ranged preview far-left

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/404](https://github.com/Ensrick/vermintide-2-tweaker/issues/404)
- Current labels: `bug, cim, diagnostics-armed, 1-major`
- Evidence class: `renderer_specific_material_closure, shared_preview_presentation_descriptor, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #406 - ct: client CTD on kill with kill-heal boon

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/406](https://github.com/Ensrick/vermintide-2-tweaker/issues/406)
- Current labels: `bug, crash, Tweaker: Chaos Wastes, 0-critical, verify-fix-coop`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #406 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #408 - wt weapon availability menu sorted by key, not name

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/408](https://github.com/Ensrick/vermintide-2-tweaker/issues/408)
- Current labels: `bug, Tweaker: Weapons, verify-fix, 2-moderate`
- Evidence class: `asset_alpha_mip_material_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #411 - wt: dead Anim Picker entry swap_charge_stance (bastard sword)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/411](https://github.com/Ensrick/vermintide-2-tweaker/issues/411)
- Current labels: `bug, Tweaker: Weapons, verify-fix, 3-low`
- Evidence class: `general_regression_and_verification_discipline`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #412 - cwv: Old Musket special-swap can't interrupt actions

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/412](https://github.com/Ensrick/vermintide-2-tweaker/issues/412)
- Current labels: `bug, CWV, 2-moderate, verify-fix-coop`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #412 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #413 - event_tweaker: shadow weave mutator crashes Adventure clients

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/413](https://github.com/Ensrick/vermintide-2-tweaker/issues/413)
- Current labels: `bug, crash, blocked, verify-fix, 0-critical, Tweaker: Events`
- Evidence class: `network_peer_parity, source_first_engine_contract, custom_asset_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #414 - cim: CW-trait reroll leaks ranged<->melee cross-slot

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/414](https://github.com/Ensrick/vermintide-2-tweaker/issues/414)
- Current labels: `bug, cim, verify-fix, 2-moderate`
- Evidence class: `network_peer_parity, source_first_engine_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #416 - cosmetics_tweaker: per-hand illusion picks don't replicate to peers

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/416](https://github.com/Ensrick/vermintide-2-tweaker/issues/416)
- Current labels: `bug, Tweaker: Cosmetics, 1-major, verify-fix-coop`
- Evidence class: `appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #416 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #417 - CWV: unit-bearing variants can silently skip transform

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/417](https://github.com/Ensrick/vermintide-2-tweaker/issues/417)
- Current labels: `bug, CWV, 2-moderate, verify-fix-coop`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #417 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #419 - CWV: illusion browser previews base mesh, no swap

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/419](https://github.com/Ensrick/vermintide-2-tweaker/issues/419)
- Current labels: `bug, CWV, verify-fix, 2-moderate`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #420 - Extract shared WeaponAppearance module across cwv/cosmetics/wt

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/420](https://github.com/Ensrick/vermintide-2-tweaker/issues/420)
- Current labels: `enhancement, CWV, cross-mod, verify-fix, 2-moderate`
- Evidence class: `renderer_specific_material_closure, unsafe_native_call_preflight, shared_preview_presentation_descriptor, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #421 - cosmetics: ct_* illusions CTD non-mod peers on equip

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/421](https://github.com/Ensrick/vermintide-2-tweaker/issues/421)
- Current labels: `bug, crash, Tweaker: Cosmetics, cross-mod, 0-critical, verify-fix-coop`
- Evidence class: `appearance_surface_fanout, network_peer_parity, bounded_transaction_lifecycle, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #421 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #423 - cwv: cloned damage_profile CTDs non-cwv host on hit

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/423](https://github.com/Ensrick/vermintide-2-tweaker/issues/423)
- Current labels: `bug, crash, CWV, 0-critical, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #423 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #424 - cwv: thrown-variant spawn RPCs CTD non-cwv clients

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/424](https://github.com/Ensrick/vermintide-2-tweaker/issues/424)
- Current labels: `bug, crash, blocked, CWV, 0-critical, verify-fix-coop`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #424 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #426 - ct: modded boons/miracles CTD non-ct peers

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/426](https://github.com/Ensrick/vermintide-2-tweaker/issues/426)
- Current labels: `bug, crash, Tweaker: Chaos Wastes, 0-critical, verify-fix-coop`
- Evidence class: `network_peer_parity, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #426 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #427 - _dbg_alert posts to chat in ~18 mods (should be printf)

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/427](https://github.com/Ensrick/vermintide-2-tweaker/issues/427)
- Current labels: `bug, cross-mod, verify-fix, 2-moderate`
- Evidence class: `network_peer_parity, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #428 - OOP: extract cross-mod duplication into shared _lib_*.lua

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/428](https://github.com/Ensrick/vermintide-2-tweaker/issues/428)
- Current labels: `enhancement, audit, refactor, cross-mod, diagnostics-armed, 2-moderate`
- Evidence class: `network_peer_parity, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #430 - event_tweaker: experimental curses CTD non-ET peers

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/430](https://github.com/Ensrick/vermintide-2-tweaker/issues/430)
- Current labels: `bug, crash, cross-mod, 1-major, Tweaker: Events, verify-fix-coop`
- Evidence class: `network_peer_parity, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #430 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #431 - wt: custom damage profiles CTD non-wt peers

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/431](https://github.com/Ensrick/vermintide-2-tweaker/issues/431)
- Current labels: `bug, crash, Tweaker: Weapons, cross-mod, 1-major, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #431 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #435 - dcp: portrait override career-scoped, not player-scoped

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/435](https://github.com/Ensrick/vermintide-2-tweaker/issues/435)
- Current labels: `bug, 2-moderate, verify-fix-coop`
- Evidence class: `appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #435 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #437 - Preserve Scoreboard Results in Adventure When Players Disconnect & Rejoin

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/437](https://github.com/Ensrick/vermintide-2-tweaker/issues/437)
- Current labels: `enhancement, Tweaker: GUI, 3-low, verify-fix-coop`
- Evidence class: `network_peer_parity`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #437 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #440 - Bardin Finds it More Difficult to Dodge Disabler Attacks Compared to Other Characters

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/440](https://github.com/Ensrick/vermintide-2-tweaker/issues/440)
- Current labels: `bug, question, Tweaker: Career, 3-low, not-started, coop-required`
- Evidence class: `network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #441 - Kerillian's Volley Crossbow equipped on Saltzpyre uses wrong inventory idle animation.

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/441](https://github.com/Ensrick/vermintide-2-tweaker/issues/441)
- Current labels: `bug, Tweaker: Weapons, verify-fix, 1-major`
- Evidence class: `shared_preview_presentation_descriptor, custom_unit_behavioral_contract, appearance_surface_fanout`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #442 - Custom per-career themed HUD elements for encasing healthbar

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/442](https://github.com/Ensrick/vermintide-2-tweaker/issues/442)
- Current labels: `enhancement, Tweaker: GUI, diagnostics-armed, 3-low`
- Evidence class: `backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #444 - Complete support for all languages Fatshark supports via Localizaiton files

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/444](https://github.com/Ensrick/vermintide-2-tweaker/issues/444)
- Current labels: `enhancement, blocked, cross-mod, diagnostics-armed, 3-low`
- Evidence class: `dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #445 - Master Toggles for Reworks

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/445](https://github.com/Ensrick/vermintide-2-tweaker/issues/445)
- Current labels: `enhancement, Tweaker: Weapons, Tweaker: Career, cross-mod, verify-fix, 1-major`
- Evidence class: `canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #446 - Mod Tweaker menu option type for Mutually Exclusive toggling

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/446](https://github.com/Ensrick/vermintide-2-tweaker/issues/446)
- Current labels: `Tweaker: GUI, verify-fix, feature, 1-major`
- Evidence class: `canonical_identity_persistence`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #447 - Zealot Devotion Talent replacement idea

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/447](https://github.com/Ensrick/vermintide-2-tweaker/issues/447)
- Current labels: `Tweaker: Career, verify-fix, feature, 3-low`
- Evidence class: `canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #450 - Boss Balance Toggles

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/450](https://github.com/Ensrick/vermintide-2-tweaker/issues/450)
- Current labels: `enhancement, verify-fix, 1-major, Tweaker: Enemies`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #451 - New Boss Ideas

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/451](https://github.com/Ensrick/vermintide-2-tweaker/issues/451)
- Current labels: `diagnostics-armed, feature, 2-moderate, Tweaker: Enemies`
- Evidence class: `general_regression_and_verification_discipline`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #452 - New Specials using Versus custom skins

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/452](https://github.com/Ensrick/vermintide-2-tweaker/issues/452)
- Current labels: `diagnostics-armed, feature, 2-moderate, Tweaker: Enemies`
- Evidence class: `custom_unit_behavioral_contract, source_first_engine_contract, custom_asset_contract`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #453 - Enemies with Special Modifiers

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/453](https://github.com/Ensrick/vermintide-2-tweaker/issues/453)
- Current labels: `diagnostics-armed, feature, 2-moderate, Tweaker: Enemies`
- Evidence class: `backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #454 - Creature Spawner should not be a hardcoded list

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/454](https://github.com/Ensrick/vermintide-2-tweaker/issues/454)
- Current labels: `enhancement, Tweaker: General, verify-fix, 2-moderate`
- Evidence class: `network_peer_parity, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #456 - Into the Nest Chaos Wastes Chest of Trials location failure

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/456](https://github.com/Ensrick/vermintide-2-tweaker/issues/456)
- Current labels: `bug, Tweaker: Chaos Wastes, diagnostics-armed, 1-major`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #457 - Revamp Mission Availability

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/457](https://github.com/Ensrick/vermintide-2-tweaker/issues/457)
- Current labels: `enhancement, Tweaker: Chaos Wastes, verify-fix, 1-major`
- Evidence class: `network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #458 - Toggle to make starting node a unique Shrine/Shop to buy/pick starting boons.

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/458](https://github.com/Ensrick/vermintide-2-tweaker/issues/458)
- Current labels: `enhancement, crash, Tweaker: Chaos Wastes, 0-critical, verify-fix-coop`
- Evidence class: `appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #458 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #460 - Chaos Wastes Tweaker Progressive Difficulty Advanced Settings

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/460](https://github.com/Ensrick/vermintide-2-tweaker/issues/460)
- Current labels: `enhancement, Tweaker: Chaos Wastes, 2-moderate, verify-fix-coop`
- Evidence class: `network_peer_parity`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #460 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #461 - Preview Starting Boons

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/461](https://github.com/Ensrick/vermintide-2-tweaker/issues/461)
- Current labels: `Tweaker: Chaos Wastes, verify-fix, feature, 1-major`
- Evidence class: `renderer_specific_material_closure, network_peer_parity, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #463 - Chest of Trials repeat trial

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/463](https://github.com/Ensrick/vermintide-2-tweaker/issues/463)
- Current labels: `bug, regression, Tweaker: Chaos Wastes, verify-fix, 1-major`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #464 - Anath Raema's Swiftness causes slower reload

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/464](https://github.com/Ensrick/vermintide-2-tweaker/issues/464)
- Current labels: `bug, Tweaker: Chaos Wastes, verify-fix, 1-major`
- Evidence class: `network_peer_parity`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #465 - Bots replacing players leaving the match and players entering the match are not given anything to compensate

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/465](https://github.com/Ensrick/vermintide-2-tweaker/issues/465)
- Current labels: `enhancement, Tweaker: Chaos Wastes, 2-moderate, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #465 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #466 - Boons for Bots idea

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/466](https://github.com/Ensrick/vermintide-2-tweaker/issues/466)
- Current labels: `enhancement, Tweaker: Chaos Wastes, 2-moderate, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #466 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #467 - Boon Price Rework

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/467](https://github.com/Ensrick/vermintide-2-tweaker/issues/467)
- Current labels: `enhancement, Tweaker: Chaos Wastes, diagnostics-armed, 2-moderate`
- Evidence class: `general_regression_and_verification_discipline`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #469 - Bots should be immune to AOE damage from Mutators like Exploding Skulls and Lightning

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/469](https://github.com/Ensrick/vermintide-2-tweaker/issues/469)
- Current labels: `enhancement, Tweaker: General, verify-fix, 1-major`
- Evidence class: `network_peer_parity, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #470 - Crash, this log is the one associated with the last small batch of chaos wastes issues.

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/470](https://github.com/Ensrick/vermintide-2-tweaker/issues/470)
- Current labels: `bug, crash, blocked, Tweaker: Chaos Wastes, verify-fix, 0-critical, vanilla-bug`
- Evidence class: `canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #471 - Increased Enemy Spawns at Chest of Trials appears to not work

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/471](https://github.com/Ensrick/vermintide-2-tweaker/issues/471)
- Current labels: `bug, Tweaker: Chaos Wastes, diagnostics-armed, 1-major`
- Evidence class: `network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #472 - Focused Spirit Rework Handmaiden

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/472](https://github.com/Ensrick/vermintide-2-tweaker/issues/472)
- Current labels: `enhancement, Tweaker: Career, verify-fix, 2-moderate`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #473 - Dance of Blades Rework Handmaiden

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/473](https://github.com/Ensrick/vermintide-2-tweaker/issues/473)
- Current labels: `enhancement, Tweaker: Career, 2-moderate, verify-fix-coop`
- Evidence class: `network_peer_parity, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #473 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #474 - CWV Musket Issues... lots of them

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/474](https://github.com/Ensrick/vermintide-2-tweaker/issues/474)
- Current labels: `bug, regression, Tweaker: Cosmetics, Tweaker: Weapons, CWV, 0-critical, verify-fix-coop`
- Evidence class: `renderer_specific_material_closure, shared_preview_presentation_descriptor, custom_unit_behavioral_contract, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #474 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #476 - Imperial Sword and Shield

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/476](https://github.com/Ensrick/vermintide-2-tweaker/issues/476)
- Current labels: `bug, CWV, diagnostics-armed, 1-major, coop-required`
- Evidence class: `appearance_surface_fanout, network_peer_parity, custom_asset_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #478 - dr_deus_01 husk spawn fails, weapon invisible

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/478](https://github.com/Ensrick/vermintide-2-tweaker/issues/478)
- Current labels: `bug, Tweaker: Cosmetics, Tweaker: Weapons, CWV, cross-mod, 1-major, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #478 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #479 - enemy_tweaker hook fallback re-runs failed CD tick

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/479](https://github.com/Ensrick/vermintide-2-tweaker/issues/479)
- Current labels: `bug, verify-fix, 1-major, Tweaker: Enemies`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #481 - CIM Athanor menu doesn't display a preview of items with LA skins

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/481](https://github.com/Ensrick/vermintide-2-tweaker/issues/481)
- Current labels: `bug, cim, Tweaker: Cosmetics, cross-mod, diagnostics-armed, 1-major`
- Evidence class: `renderer_specific_material_closure, shared_preview_presentation_descriptor, custom_unit_behavioral_contract, canonical_identity_persistence, custom_asset_contract`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #482 - CWV: Crafted variants lose canonical transforms

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/482](https://github.com/Ensrick/vermintide-2-tweaker/issues/482)
- Current labels: `bug, regression, CWV, 2-moderate, verify-fix-coop`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #482 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #483 - CWV: Dual Weapons lack Individualized cosmetic changing and don't display properly for players in lobby.

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/483](https://github.com/Ensrick/vermintide-2-tweaker/issues/483)
- Current labels: `bug, Tweaker: Cosmetics, CWV, 2-moderate, verify-fix-coop`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #483 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #484 - Yet more CWV Musket issues

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/484](https://github.com/Ensrick/vermintide-2-tweaker/issues/484)
- Current labels: `bug, CWV, diagnostics-armed, 0-critical, coop-required`
- Evidence class: `network_peer_parity, canonical_identity_persistence, custom_asset_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #485 - Unlock Option of Heroic Poses in Modded

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/485](https://github.com/Ensrick/vermintide-2-tweaker/issues/485)
- Current labels: `Tweaker: Cosmetics, diagnostics-armed, feature, 3-low`
- Evidence class: `backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #487 - Chaos Wastes game Freeze

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/487](https://github.com/Ensrick/vermintide-2-tweaker/issues/487)
- Current labels: `bug, Tweaker: Chaos Wastes, diagnostics-armed, 0-critical`
- Evidence class: `network_peer_parity, canonical_identity_persistence`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #488 - Additional Bot Improvement Ideas 7/11/2026

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/488](https://github.com/Ensrick/vermintide-2-tweaker/issues/488)
- Current labels: `Tweaker: General, diagnostics-armed, feature, coop-required`
- Evidence class: `network_peer_parity, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #490 - gt stable carries pre-459 world-liveness bugs

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/490](https://github.com/Ensrick/vermintide-2-tweaker/issues/490)
- Current labels: `bug, Tweaker: General, verify-fix, 1-major`
- Evidence class: `custom_unit_behavioral_contract, canonical_identity_persistence, bounded_transaction_lifecycle`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #491 - cwv pairing skins ride wire un-nulled, CTD non-cwv peers

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/491](https://github.com/Ensrick/vermintide-2-tweaker/issues/491)
- Current labels: `bug, crash, CWV, cross-mod, 0-critical, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #491 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #498 - Enforce lifecycle labels, roll out not-started

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/498](https://github.com/Ensrick/vermintide-2-tweaker/issues/498)
- Current labels: `enhancement, tooling, 2-moderate, not-started`
- Evidence class: `network_peer_parity`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #499 - Consolidate per-issue probes into diagnostics modules

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/499](https://github.com/Ensrick/vermintide-2-tweaker/issues/499)
- Current labels: `enhancement, refactor, cross-mod, verify-fix, 2-moderate`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #504 - OOP decomposition umbrella: remaining phases

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/504](https://github.com/Ensrick/vermintide-2-tweaker/issues/504)
- Current labels: `enhancement, audit, refactor, 1-major, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #504 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #505 - Single Mission Loader redesign

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/505](https://github.com/Ensrick/vermintide-2-tweaker/issues/505)
- Current labels: `Tweaker: Chaos Wastes, verify-fix, feature, 0-critical`
- Evidence class: `network_peer_parity, canonical_identity_persistence, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #509 - thin regression harness backfill: WOC, enemy, dcp, mp

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/509](https://github.com/Ensrick/vermintide-2-tweaker/issues/509)
- Current labels: `enhancement, cross-mod, verify-fix, 2-moderate`
- Evidence class: `network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #511 - rt checks: io.open throws in VMF sandbox

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/511](https://github.com/Ensrick/vermintide-2-tweaker/issues/511)
- Current labels: `bug, cross-mod, verify-fix, 1-major`
- Evidence class: `canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #512 - et suite: keep-timing mini_patrol false negative

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/512](https://github.com/Ensrick/vermintide-2-tweaker/issues/512)
- Current labels: `bug, verify-fix, 3-low, Tweaker: Enemies`
- Evidence class: `source_first_engine_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #518 - Loremaster Cosmetics overriding upgrade cosmetics in Chaos Wastes

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/518](https://github.com/Ensrick/vermintide-2-tweaker/issues/518)
- Current labels: `bug, Tweaker: Chaos Wastes, Tweaker: Cosmetics, verify-fix, 1-major`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #522 - Add a darker-lighting control for the inventory character preview

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/522](https://github.com/Ensrick/vermintide-2-tweaker/issues/522)
- Current labels: `Tweaker: GUI, verify-fix, feature, 3-low`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, custom_asset_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #524 - Crafted CWV items are creating more base-item instances.

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/524](https://github.com/Ensrick/vermintide-2-tweaker/issues/524)
- Current labels: `bug, cim, CWV, diagnostics-armed, 0-critical`
- Evidence class: `canonical_identity_persistence, bounded_transaction_lifecycle, custom_asset_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #526 - Portrait frame issue on mission completion menu.

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/526](https://github.com/Ensrick/vermintide-2-tweaker/issues/526)
- Current labels: `bug, diagnostics-armed, 3-low, dcp`
- Evidence class: `asset_alpha_mip_material_contract, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, custom_asset_contract, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #528 - Crosshair Kill Confirmation Options.

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/528](https://github.com/Ensrick/vermintide-2-tweaker/issues/528)
- Current labels: `bug, regression, Tweaker: GUI, verify-fix, 0-critical`
- Evidence class: `renderer_specific_material_closure, network_peer_parity, canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #531 - boss balance: behavioral knobs need runtime hooks

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/531](https://github.com/Ensrick/vermintide-2-tweaker/issues/531)
- Current labels: `enhancement, verify-fix, 2-moderate, Tweaker: Enemies`
- Evidence class: `network_peer_parity, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #533 - The Collectibles for Chaos Wastes Mission on tab

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/533](https://github.com/Ensrick/vermintide-2-tweaker/issues/533)
- Current labels: `bug, Tweaker: Chaos Wastes, diagnostics-armed, 2-moderate`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #540 - Harden CI and protect master

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/540](https://github.com/Ensrick/vermintide-2-tweaker/issues/540)
- Current labels: `enhancement, audit, tooling, diagnostics-armed, 1-major`
- Evidence class: `canonical_identity_persistence`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #546 - Professionalize repository engineering and contributor workflow

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/546](https://github.com/Ensrick/vermintide-2-tweaker/issues/546)
- Current labels: `enhancement, audit, tooling, verify-fix, 1-major`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #547 - HUD edit drag box offset from element

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/547](https://github.com/Ensrick/vermintide-2-tweaker/issues/547)
- Current labels: `bug, Tweaker: GUI, verify-fix, 2-moderate`
- Evidence class: `canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #548 - Troll Bile and Debuffs affect godmode

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/548](https://github.com/Ensrick/vermintide-2-tweaker/issues/548)
- Current labels: `bug, Tweaker: General, diagnostics-armed, 3-low`
- Evidence class: `general_regression_and_verification_discipline`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #549 - Give more damage in godmode

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/549](https://github.com/Ensrick/vermintide-2-tweaker/issues/549)
- Current labels: `enhancement, Tweaker: General, 2-moderate, verify-fix-coop`
- Evidence class: `network_peer_parity, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #549 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #556 - Granting talents as starting boons

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/556](https://github.com/Ensrick/vermintide-2-tweaker/issues/556)
- Current labels: `bug, Tweaker: Chaos Wastes, verify-fix, 2-moderate`
- Evidence class: `canonical_identity_persistence`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #557 - [mod] Tweaker: GUI layout wrong for mod settings

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/557](https://github.com/Ensrick/vermintide-2-tweaker/issues/557)
- Current labels: `bug, verify-fix, 0-critical`
- Evidence class: `asset_alpha_mip_material_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #558 - Stop tracking generated bundle outputs

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/558](https://github.com/Ensrick/vermintide-2-tweaker/issues/558)
- Current labels: `enhancement, audit, tooling, diagnostics-armed, 2-moderate`
- Evidence class: `bounded_transaction_lifecycle`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #564 - CT mission depth localization throws five exceptions

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/564](https://github.com/Ensrick/vermintide-2-tweaker/issues/564)
- Current labels: `bug, Tweaker: Chaos Wastes, verify-fix, 2-moderate`
- Evidence class: `canonical_identity_persistence, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #565 - cosmetics: offhand preload performs 74 blocking synchronous package loads at startup

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/565](https://github.com/Ensrick/vermintide-2-tweaker/issues/565)
- Current labels: `bug, Tweaker: Cosmetics, verify-fix, 2-moderate`
- Evidence class: `unsafe_native_call_preflight, shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #566 - cosmetics: white_glow regression test contradicts known vanilla template set

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/566](https://github.com/Ensrick/vermintide-2-tweaker/issues/566)
- Current labels: `bug, Tweaker: Cosmetics, verify-fix, 3-low`
- Evidence class: `canonical_identity_persistence`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #567 - CWV: three weapon skins fail vanilla configuration validation

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/567](https://github.com/Ensrick/vermintide-2-tweaker/issues/567)
- Current labels: `bug, CWV, 2-moderate, verify-fix-coop`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #567 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #571 - ct: injected Adventure collectibles overflow Chaos Wastes Tab overlay

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/571](https://github.com/Ensrick/vermintide-2-tweaker/issues/571)
- Current labels: `bug, Tweaker: Chaos Wastes, verify-fix, 2-moderate`
- Evidence class: `source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #573 - mp: generate persistent modded dailies and isolate Silver Shillings

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/573](https://github.com/Ensrick/vermintide-2-tweaker/issues/573)
- Current labels: `Progression, verify-fix, feature, 1-major`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #576 - wt: audit missing Saltzpyre animation-tuner ports; crowbill falsely confirmed

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/576](https://github.com/Ensrick/vermintide-2-tweaker/issues/576)
- Current labels: `bug, Tweaker: Weapons, 2-moderate, verify-fix-coop`
- Evidence class: `appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #576 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #577 - mp: implement backend-free Emporium purchases with modded Silver Shillings

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/577](https://github.com/Ensrick/vermintide-2-tweaker/issues/577)
- Current labels: `Progression, verify-fix, feature, 1-major`
- Evidence class: `canonical_identity_persistence, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #578 - Label and Refresh Local Silver Shillings

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/578](https://github.com/Ensrick/vermintide-2-tweaker/issues/578)
- Current labels: `enhancement, Progression, verify-fix, 2-moderate`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #579 - cwv: restore dual-axes cosmetic parity

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/579](https://github.com/Ensrick/vermintide-2-tweaker/issues/579)
- Current labels: `bug, CWV, 2-moderate, verify-fix-coop`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #579 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #583 - Cosmetics: customize dual-weapon offhands

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/583](https://github.com/Ensrick/vermintide-2-tweaker/issues/583)
- Current labels: `enhancement, Tweaker: Cosmetics, CWV, 2-moderate, verify-fix-coop`
- Evidence class: `renderer_specific_material_closure, shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #583 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #586 - CWV: Dual Axes state-machine crash

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/586](https://github.com/Ensrick/vermintide-2-tweaker/issues/586)
- Current labels: `bug, crash, regression, CWV, 0-critical, verify-fix-coop`
- Evidence class: `unsafe_native_call_preflight, network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #586 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #588 - CWV: Dual Maces crash clients on wield

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/588](https://github.com/Ensrick/vermintide-2-tweaker/issues/588)
- Current labels: `bug, CWV, 0-critical, verify-fix-coop`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #588 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #590 - ct: Pool aliases exceed level capacity

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/590](https://github.com/Ensrick/vermintide-2-tweaker/issues/590)
- Current labels: `bug, crash, Tweaker: Chaos Wastes, verify-fix, 0-critical`
- Evidence class: `network_peer_parity, canonical_identity_persistence`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #598 - CIM: restore TAB modded frame without leaking custom resources

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/598](https://github.com/Ensrick/vermintide-2-tweaker/issues/598)
- Current labels: `bug, cim, 2-moderate, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, custom_asset_contract`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #598 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #599 - CWV: default-on mace and hammer identity toggle

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/599](https://github.com/Ensrick/vermintide-2-tweaker/issues/599)
- Current labels: `enhancement, CWV, verify-fix, 2-moderate`
- Evidence class: `network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #600 - Fix Bot "Wait!" Command in Command Wheel Not Stopping Bot Where the Player is Looking

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/600](https://github.com/Ensrick/vermintide-2-tweaker/issues/600)
- Current labels: `bug, Tweaker: General, verify-fix, 2-moderate`
- Evidence class: `backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #601 - WT: add Greataxe and Dual Axes identity balance toggles

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/601](https://github.com/Ensrick/vermintide-2-tweaker/issues/601)
- Current labels: `enhancement, Tweaker: Weapons, verify-fix, 1-major`
- Evidence class: `canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #602 - Add CWV Dawi Mace weapon family

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/602](https://github.com/Ensrick/vermintide-2-tweaker/issues/602)
- Current labels: `enhancement, blocked, Tweaker: Weapons, CWV, 2-moderate, not-started`
- Evidence class: `renderer_specific_material_closure, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #604 - cwv: add licensed Dawi and Imperial Crowbill weapon family

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/604](https://github.com/Ensrick/vermintide-2-tweaker/issues/604)
- Current labels: `crash, regression, Tweaker: Weapons, CWV, feature, 0-critical, verify-fix-coop`
- Evidence class: `renderer_specific_material_closure, shared_preview_presentation_descriptor, custom_unit_behavioral_contract, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #604 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #605 - Create Character Dialogue player and controls

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/605](https://github.com/Ensrick/vermintide-2-tweaker/issues/605)
- Current labels: `Tweaker: GUI, cross-mod, verify-fix, feature, 1-major, Character Dialogue`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #607 - Reward modded missions with local loot chests

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/607](https://github.com/Ensrick/vermintide-2-tweaker/issues/607)
- Current labels: `Progression, diagnostics-armed, feature, 1-major`
- Evidence class: `network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #608 - Research Steam-loss LAN recovery for modded play

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/608](https://github.com/Ensrick/vermintide-2-tweaker/issues/608)
- Current labels: `Tweaker: General, cross-mod, feature, 1-major, not-started`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #610 - Restore native weapon glow defaults

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/610](https://github.com/Ensrick/vermintide-2-tweaker/issues/610)
- Current labels: `bug, regression, Tweaker: Cosmetics, verify-fix, 1-major`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #611 - Add Master Toggles for Selecting Multiple Weapons for Weapon Availability

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/611](https://github.com/Ensrick/vermintide-2-tweaker/issues/611)
- Current labels: `Tweaker: Weapons, verify-fix, feature, 1-major`
- Evidence class: `asset_alpha_mip_material_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #613 - Author WOC trophy weapon models

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/613](https://github.com/Ensrick/vermintide-2-tweaker/issues/613)
- Current labels: `bug, 1-major, WOC, verify-fix-coop`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, custom_asset_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #613 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #614 - Author Skarrik champion halberd

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/614](https://github.com/Ensrick/vermintide-2-tweaker/issues/614)
- Current labels: `feature, 1-major, WOC, not-started`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, bounded_transaction_lifecycle`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #615 - Author Skarrik dual swords

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/615](https://github.com/Ensrick/vermintide-2-tweaker/issues/615)
- Current labels: `feature, 1-major, WOC, not-started`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, bounded_transaction_lifecycle, custom_asset_contract`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #619 - Add Foot Knight career feature toggles

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/619](https://github.com/Ensrick/vermintide-2-tweaker/issues/619)
- Current labels: `Tweaker: Career, feature, 2-moderate, verify-fix-coop`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #619 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #620 - Add per-item combat style switching

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/620](https://github.com/Ensrick/vermintide-2-tweaker/issues/620)
- Current labels: `crash, CWV, cross-mod, verify-fix, feature, 0-critical`
- Evidence class: `renderer_specific_material_closure, unsafe_native_call_preflight, shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #625 - Reconcile unmerged agent branches

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/625](https://github.com/Ensrick/vermintide-2-tweaker/issues/625)
- Current labels: `enhancement, tooling, 1-major, not-started`
- Evidence class: `source_first_engine_contract, backend_realm_isolation`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #626 - ET: Dissect Feast mission activation

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/626](https://github.com/Ensrick/vermintide-2-tweaker/issues/626)
- Current labels: `enhancement, 1-major, Tweaker: Events, verify-fix-coop`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, source_first_engine_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #626 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #627 - Add custom Outrider launcher model

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/627](https://github.com/Ensrick/vermintide-2-tweaker/issues/627)
- Current labels: `enhancement, blocked, CWV, 1-major, not-started`
- Evidence class: `appearance_surface_fanout, network_peer_parity, custom_asset_contract`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #628 - CIM: unify synthetic weapon contract and salvage eligibility

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/628](https://github.com/Ensrick/vermintide-2-tweaker/issues/628)
- Current labels: `bug, cim, CWV, cross-mod, verify-fix, 1-major`
- Evidence class: `shared_preview_presentation_descriptor, canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #629 - Cosmetics: complete Grail Knight Purpure and Azure set

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/629](https://github.com/Ensrick/vermintide-2-tweaker/issues/629)
- Current labels: `enhancement, Tweaker: Cosmetics, feature, 2-moderate, verify-fix-coop`
- Evidence class: `renderer_specific_material_closure, shared_preview_presentation_descriptor, custom_unit_behavioral_contract, asset_alpha_mip_material_contract, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, custom_asset_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #629 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #630 - Renderer freeze: DX12 fence timeout after entering Mod Tweaker Weapons tab

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/630](https://github.com/Ensrick/vermintide-2-tweaker/issues/630)
- Current labels: `crash, Tweaker: GUI, Tweaker: Weapons, cross-mod, diagnostics-armed, 0-critical`
- Evidence class: `canonical_identity_persistence, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: run documented repro and collect bounded diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue's bounded armed repro records a first state divergence.
- **Change:** Repair only the layer named by that trace.
- **Falsifier:** The trace remains healthy through the observed symptom.

**Fallback 2**

- **Evidence/trigger:** Captured runtime state differs from the issue's cited vanilla/decompiled consumer contract.
- **Change:** Repair the first contract mismatch and retain the probe as regression evidence.
- **Falsifier:** Captured state matches the source contract at every sampled boundary.

**Fallback 3**

- **Evidence/trigger:** Insufficient evidence: the current probe is silent or cannot distinguish the remaining candidates.
- **Change:** Move bounded instrumentation one lifecycle edge earlier and later; promote only the proven edge to a fix.
- **Falsifier:** The existing probe already identifies one causal boundary.

## #631 - Allow GUI Tweaker Hot Keys to Track Mouse Key Binds

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/631](https://github.com/Ensrick/vermintide-2-tweaker/issues/631)
- Current labels: `enhancement, Tweaker: GUI, verify-fix, 3-low`
- Evidence class: `custom_unit_behavioral_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #632 - WOC: make Blightreaper a cursed Shyish weapon

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/632](https://github.com/Ensrick/vermintide-2-tweaker/issues/632)
- Current labels: `feature, 1-major, WOC, not-started`
- Evidence class: `network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, backend_realm_isolation`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #633 - WOC: give Blightreaper localized spatial audio and inspect whispers

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/633](https://github.com/Ensrick/vermintide-2-tweaker/issues/633)
- Current labels: `feature, 2-moderate, WOC, not-started`
- Evidence class: `custom_unit_behavioral_contract, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: scope against source, then implement or arm diagnostics

**Fallback 1**

- **Evidence/trigger:** The issue body and cited source establish a bounded acceptance contract.
- **Change:** Implement that contract on current canonical source with a truth-table regression.
- **Falsifier:** Source/runtime evidence contradicts a required premise in the accepted contract.

**Fallback 2**

- **Evidence/trigger:** Insufficient evidence: no runtime trace yet distinguishes the candidate engine/UI/inventory boundaries.
- **Change:** Add a minimal repro and bounded trace at the named boundary, then repair only the first observed divergence.
- **Falsifier:** Existing evidence already identifies the divergent boundary.

**Fallback 3**

- **Evidence/trigger:** The requested path is blocked by absent provenance/license, resource residency, or external service authority.
- **Change:** Retain a resident vanilla fallback or keep the feature disabled until the missing evidence/authority exists.
- **Falsifier:** The required provenance, resource closure, and authority are all positively proved.

## #634 - WT: refresh dev stream after beta

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/634](https://github.com/Ensrick/vermintide-2-tweaker/issues/634)
- Current labels: `enhancement, Tweaker: Weapons, tooling, verify-fix, 2-moderate`
- Evidence class: `canonical_identity_persistence, source_first_engine_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #635 - WT: strip dev UI from beta

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/635](https://github.com/Ensrick/vermintide-2-tweaker/issues/635)
- Current labels: `bug, regression, Tweaker: Weapons, verify-fix, 1-major`
- Evidence class: `source_first_engine_contract, dynamic_localization_ui_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #636 - WT v0.12.139-dev Missing Weapons Tab on GUI Tweaker

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/636](https://github.com/Ensrick/vermintide-2-tweaker/issues/636)
- Current labels: `bug, Tweaker: GUI, Tweaker: Weapons, cross-mod, verify-fix, 1-major`
- Evidence class: `network_peer_parity`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #637 - Make WOC items unique inventory relics

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/637](https://github.com/Ensrick/vermintide-2-tweaker/issues/637)
- Current labels: `cim, cross-mod, verify-fix, feature, 1-major, WOC`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #638 - Add final icons for the Purpure and Azure Grail Knight cosmetic set

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/638](https://github.com/Ensrick/vermintide-2-tweaker/issues/638)
- Current labels: `Tweaker: Cosmetics, verify-fix, feature, 3-low`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, canonical_identity_persistence, bounded_transaction_lifecycle, custom_asset_contract, backend_realm_isolation`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #639 - Finalize names and flavor text for the Purpure and Azure Grail Knight cosmetic set

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/639](https://github.com/Ensrick/vermintide-2-tweaker/issues/639)
- Current labels: `Tweaker: Cosmetics, feature, 3-low, verify-fix-coop`
- Evidence class: `shared_preview_presentation_descriptor, network_peer_parity, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #639 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.

## #640 - enemy: Deleted poison source crashes damage hook

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/640](https://github.com/Ensrick/vermintide-2-tweaker/issues/640)
- Current labels: `bug, crash, verify-fix, 0-critical, Tweaker: Enemies`
- Evidence class: `unsafe_native_call_preflight, network_peer_parity, source_first_engine_contract`
- Current action: solo in-game verification

**Fallback 1**

- **Evidence/trigger:** The issue's posted build-specific verification fails at a named invariant or surface.
- **Change:** Repair the first failed invariant in the current implementation, scoped to that surface.
- **Falsifier:** The invariant passes while the reported symptom remains.

**Fallback 2**

- **Evidence/trigger:** Runtime evidence shows the custom hook/adapter disagrees with the cited vanilla consumer contract.
- **Change:** Replace or move the custom seam to that source-backed vanilla boundary, preserving fail-closed behavior.
- **Falsifier:** The custom and vanilla boundary inputs/outputs are identical.

**Fallback 3**

- **Evidence/trigger:** The loaded version/hash or canonical ancestry does not contain the claimed fix.
- **Change:** Reconcile the issue commit onto current master, rebuild, deploy, and hash-verify before changing behavior.
- **Falsifier:** The failing log and deployed hash prove the current canonical commit was running.

## #641 - cosmetics: Add independent offhand illusion names

- Tracker: [https://github.com/Ensrick/vermintide-2-tweaker/issues/641](https://github.com/Ensrick/vermintide-2-tweaker/issues/641)
- Current labels: `Tweaker: Cosmetics, feature, 2-moderate, verify-fix-coop`
- Evidence class: `shared_preview_presentation_descriptor, appearance_surface_fanout, network_peer_parity, canonical_identity_persistence, bounded_transaction_lifecycle, custom_asset_contract, dynamic_localization_ui_contract, backend_realm_isolation`
- Current action: two-player in-game verification

**Fallback 1**

- **Evidence/trigger:** The posted host/client verification for #641 fails and paired logs identify the first divergent peer/state.
- **Change:** Repair that first owner/husk/RPC/lookup divergence at the existing issue-scoped boundary.
- **Falsifier:** Both peers log identical authoritative state before the visible failure.

**Fallback 2**

- **Evidence/trigger:** Paired evidence shows authority or replay occurs on the wrong peer/lifecycle edge.
- **Change:** Move ownership to the source-backed vanilla authority and transmit only bounded lookup-safe identity/state.
- **Falsifier:** Authority, sender authentication, and lifecycle replay are already identical on both peers.

**Fallback 3**

- **Evidence/trigger:** Failure occurs only when a peer lacks the mod, capability, lookup entry, or renderer resource.
- **Change:** Parity-gate the optional feature and select a resident vanilla fallback for that peer.
- **Falsifier:** The failing peer proves positive parity and local resource closure.
