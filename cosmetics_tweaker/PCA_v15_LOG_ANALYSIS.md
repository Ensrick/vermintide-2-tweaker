## PC-A v0.9.0.15-hotfix Log Analysis

**Log:** `console-2026-05-20-03.47.41-baacb2bb-b713-4d02-89c2-ee582e5c01f7.log` (5.3 MB)
**CT mod version:** Cosmetics Tweaker v0.9.0.15-hotfix (line 1271-1272)
**PC-A peer_id:** `11000010ef3befb`
**Lyndsey peer_id:** `11000013cb862af`

---

## 1. PC-A's role this session: HOST first, then CLIENT

PC-A started the session as a solo lobby HOST, dropped that session, and re-joined into Lyndsey's lobby as CLIENT for the remainder of the test.

| Line | Time | Event |
|---|---|---|
| 1271 | 03:48:16.826 | `Cosmetics Tweaker v0.9.0.15-hotfix loaded` |
| 3085 | 03:48:36.098 | `[PeerSM] 11000010ef3befb :: on_enter Connecting` (own lobby) |
| 3112 | 03:48:36.288 | `host_peer_id:11000010ef3befb my_peer_id:11000010ef3befb` — **HOST of own session** |
| 4942 | 03:54:18.417 | `Connecting to game session.` (joining Lyndsey) |
| 4949 | 03:54:18.570 | `Connected to host: 11000013cb862af, using channel: 1` — **CLIENT now** |
| 5025 | 03:54:22.912 | `[cos_glow_apply] peer 11000010ef3befb left — purging _glow_by_peer entry` — own host session torn down |
| 5092 | 03:54:22.949 | `host_peer_id:11000013cb862af my_peer_id:11000010ef3befb` — fully reseated as CLIENT |

The interesting test window is **03:54:22 → end of log**, i.e. ~37 minutes as CLIENT in Lyndsey's lobby.

---

## 2. Did v0.9.0.15's host-peer-id nil-guard fire? Untestable — no emits at all

The 0.9.0.15 hotfix targets the CLIENT branch of `_send_la_apply`. To exercise it PC-A would need to call `_send_la_apply` while a CLIENT. **It was never called.**

| Search | Hits |
|---|---|
| `[cos_la_apply emit] HOST` | 0 |
| `[cos_la_apply emit] CLIENT->req` | 0 |
| `[cos_la_apply emit] CLIENT->req DEFERRED` | 0 |
| `[cos_la_apply recv]` / `CACHE WRITE` | 0 |
| `[net-safe] update_cosmetic_slot` runtime hit | 0 (only the boot-time registration line at 1319) |
| `[LA paint]` non-skip ("applying" / "ok") | 0 (178 `skip:` lines, all `has_skin=false` or `no _offhand_selection`) |
| `[husk-mesh-swap` APPLIED (vs `probe`) | 0 (all 2,184 events are `probe` with `cache_has_wearer=false`) |
| husk-mesh-swap probes for PC-A's own peer | 0 |
| husk-mesh-swap probes for Lyndsey's peer | 2,184 |

The CLIENT->req path of the hotfix was never reached because PC-A's user did not equip any LA-substituted item during the session. No `CosmeticUtils.update_cosmetic_slot` invocation, no `PUAE.spawn_resynced_loadout` LA branch, no `AttachmentUtils.hot_join_sync` LA branch fired with `la_substitute()` returning non-nil. Without an LA equip event, `_send_la_apply` simply isn't called from any of its 6 call sites.

The **inbound** path is verifiable independently: PC-A also received zero `cos_la_apply` broadcasts from the host. That matches Lyndsey's parallel log (`LYNDSEY_v15_LOG_ANALYSIS.md`): she likewise never emitted any `cos_la_apply` even though she is HOST. The whole bus was silent both directions.

---

## 3. Full sync state for cosmetics PC-A equipped

**None.** PC-A's user did not equip any LA-bridged items this session. The user did open the inventory previewer (240 `[LA preview] backend-resolved skin` lines) and the LA bridge resolved skins like `dr_1h_throwing_axes_skin_02_magic_01`, `wh_repeating_crossbow_skin_02_magic_01`, `wh_fencing_sword_skin_07_magic_01`, `wh_1h_axe_skin_06_magic_01` — but those are **preview-only** events from `MenuWorldPreviewer.equip_item`, not commit events through `update_cosmetic_slot`.

Therefore PC-A's `_la_equips_by_peer` for itself is empty, no broadcast went out, and Lyndsey's PC has nothing to apply.

For incoming Lyndsey gear: every wield she performed on her side produced a probe on PC-A (2,184 of them — `slot_ranged shortbow_template_1`, `slot_melee flaming_sword_template_1`, `slot_melee es_deus_01_template`, `slot_melee one_handed_spears_shield_template`, `slot_career_skill_weapon bw_necromancer_career_skill_weapon`, `slot_ranged blunderbuss_template_1`, `slot_ranged bw_deus_01_template_1`, etc.). Every single probe reports `cache_has_wearer=false cache_has_entry=false entry_kind=nil entry_key=nil`. PC-A's `_la_equips_by_peer[11000013cb862af]` table never received a CACHE WRITE because Lyndsey never broadcast a `cos_la_apply` for any of her equips.

---

## 4. New error patterns

No new errors. PC-A's log is clean of CT errors, nil-value crashes, RPC reject lines, or `dependency missing` warnings. Engine-level noise (DLSS streamline OTA failures, the `divine_*` xbox achievement misses, ResourceManager `Don't know how to load #ID[...]` warnings around 03:48:11 - pre-mod-load) is pre-existing background.

Only CT log around the role flip is the cleanup line at 5025: `[cos_glow_apply] peer 11000010ef3befb left — purging _glow_by_peer entry` — that fires when PC-A's own peer detaches from its solo host session before joining Lyndsey. Expected.

The "loremasters requirement issue" Lyndsey reports is consistent with this analysis: PC-A is wearing LA gear that displays correctly to itself (LA's own first-party rendering), but the cosmetics_tweaker bridge never broadcast the substitution to peers, so Lyndsey sees the vanilla fallback / generic mesh. The fix Lyndsey needs is **PC-A actually triggering an equip-commit event** — opening the customization menu, picking an illusion/hat/skin, and pressing the commit button — which would route through `CosmeticUtils.update_cosmetic_slot` and reach `_send_la_apply`.

---

## 5. Where to look next

- The `update_cosmetic_slot` hook IS installed (`[net-safe] hook registration: CosmeticUtils=true LoadoutUtils=true AttachmentUtils=true PUAE=true` at line 1319) but never runs. If the user *did* equip items during this session and the hook still didn't fire, that's a hook-registration silently-shadowed bug.
- The `PUAE.spawn_resynced_loadout` hook should fire automatically on hot-join when an LA-equipped wearer is in the lobby. It did not. Either no one in the lobby is wearing LA gear (per `_la_substitute_name` returning nil), or the hook never reached the LA branch.
- The `AttachmentUtils.hot_join_sync` hook similarly should fire when PC-A joined Lyndsey's lobby at 03:54:22 if Lyndsey was wearing LA cosmetics. It did not — strong indication Lyndsey's keep loadout has no LA bid in `slot_data.name`.

Recommended verification: have PC-A open the Athanor/customization menu, equip an LA illusion onto a weapon, hit commit, and re-capture the log. The `[cos_la_apply emit] CLIENT->req` line MUST appear within ~100ms of the click. If it doesn't, the v0.9.0.15 fix is dead-code and the bug is upstream of `_send_la_apply` (likely the `la_substitute_name` matcher or the hook chain).
