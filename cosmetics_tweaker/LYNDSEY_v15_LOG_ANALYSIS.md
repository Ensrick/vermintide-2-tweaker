# Lyndsey v0.9.0.15-hotfix Log Analysis

**Log:** `console-2026-05-20-03.51.13-d70a97fc-84bc-4d60-b2d8-40f665c74d9e.log` (29,043 lines, ~3.1 MB)
**CT bridge version:** Cosmetics Tweaker v0.9.0.15-hotfix (line 1271/1272)
**Session window:** 03:51:13 boot through ~05:11:55 game-state churn

---

## 1. Lyndsey's role this session: HOST

**Evidence:**

| Line | Event |
|---|---|
| 2617 | `<<crashify-property>>peer_id = 11000013cb862af<</crashify-property>>` — her own peer |
| 2688 | `[ChatManager] Setting up network context, host_peer_id:11000013cb862af my_peer_id:11000013cb862af` |
| 2847 | `[Gamestate] Enter StateIngame HOST` |
| 2872 | `[Matchmaking] my_peer_id: 11000013cb862af, I am server` |
| 3474 | `Client with peer_id 11000010ef3befb got APPROVED by server` — PC-A joins as CLIENT |
| 3515-3522 | `[ProfileSynchronizer] Running hot_join_sync for peer 11000010ef3befb` |
| 3577 | `peer_hot_join_synced:11000010ef3befb:...:0 = true` — PC-A finishes hot-join |
| 3952 | `[ct][INFO] [ct_peers] HOST peer=self (host) ct=0.7.69-alpha ...` — confirms her CT instance flagged itself HOST |

Lyndsey hosts; PC-A is her CLIENT.

---

## 2. Did she receive any cos_la_apply events? NO. Zero. Entire session.

| Search | Result |
|---|---|
| `cos_la_apply` | **0 hits** in 29,043 lines |
| `cos_la_req` / `cos_la_apply_req` | **0 hits** |
| `[CACHE WRITE]` | **0 hits** |
| `[cos_la_apply emit]` / `[cos_la_apply recv]` | **0 hits** |
| `[husk-hat-create]` | **0 hits** |
| `husk-wield-wrap` events (PC-A wearer) | 1,086 hits — all with `cache_has_wearer=false cache_has_entry=false` |
| Unique husk-mesh-swap template names observed | `one_handed_swords_template_1`, `repeating_crossbow_template_1`, `we_one_hand_sword_template_1`, `crossbow_template_1`, `victor_bountyhunter_career_skill_weapon`, `nil` |

**Key inference:** None of the templates broadcast over PC-A's husk are LA variants (no `la_*`, no `lm_*`, no `cwv_*` prefixes). PC-A apparently isn't equipped with any LA item this session, so PC-A's bridge has no `cos_la_apply` to broadcast in the first place. The receive chain has nothing to receive — not because it's broken, but because there's no inbound LA traffic.

**Sister-system sanity check (proves networking layer is alive):**
- Line 3576: `[hot-join glow replay] sent 1 cos_glow_apply entries targeted at joiner=11000010ef3befb` — Lyndsey's glow replay fires correctly to PC-A on join.
- Lines 4032, 4551, … 28672: `[cos_glow_apply] peer 11000013cb862af left — purging _glow_by_peer entry` repeats 12 times across the session.
- `[net-safe] hook registration: CosmeticUtils=true LoadoutUtils=true AttachmentUtils=true PUAE=true` (line 1319) — all wire-up hooks succeeded.
- `[LA bridge] registered 35 items, skipped 0` + `apply gate installed (raw replacement)` (lines 1700-1701).

The full cos_la_apply send/recv pipeline is *wired* but never *exercised*.

---

## 3. "Loremasters requirement" chat warning text: NOT PRESENT

Searched the entire log for every plausible substring of the v0.9.0.14 warning text:

| Substring | Hits |
|---|---|
| `Loremaster's Armoury is NOT` | 0 |
| `LA cosmetics from other players will NOT render` | 0 |
| `LA variant '.*' missing from your local LA install` | 0 |
| `is NOT enabled` | 0 |
| `missing from your local` | 0 |
| `will NOT render` | 0 |
| `requires.*Loremaster` | 0 |
| `LA install` | 0 |
| `[cosmetics_tweaker][ECHO]` after boot banner | 0 (only the v0.9.0.15-hotfix boot banner at line 1272) |

The v0.9.0.14 chat-warning code **did not fire at all this session.** No `mod:echo` Loremaster-related output appears anywhere.

---

## 4. LA-related event timeline

| Time | Line | Event |
|---|---|---|
| 03:51:51 | 725 | Loremaster's Armoury mod enabled in launcher |
| 03:51:52 | 858 | `la_prefix_patch v0.3.1-dev` boots |
| 03:51:53 | 864 | LA crashify property registers |
| 03:51:56 | 867 | LA VMF init |
| 03:51:57 | 876-1059 | LA registers ~180 hooks (PackageManager, AttachmentUtils, HeroPreviewer, etc.) |
| 03:52:00 | 1271 | cosmetics_tweaker v0.9.0.15-hotfix loaded |
| 03:52:00 | 1319 | `[net-safe] hook registration: CosmeticUtils=true LoadoutUtils=true AttachmentUtils=true PUAE=true` |
| 03:52:01 | 1693 | `[LA bridge] pre_register_la_inventory_packages: 31 variant(s) registered (sorted, all kind=unit)` |
| 03:52:01 | 1700 | `[LA bridge] registered 35 items, skipped 0 (no vanilla unit match)` |
| 03:52:01 | 1701 | `[LA bridge] apply gate installed (raw replacement)` |
| 03:53:25 | 2617 | Lyndsey's peer_id set: `11000013cb862af` |
| 03:53:33 | 2847 | Enter StateIngame as HOST |
| 03:53:37 | 3286-3307 | `[LA preview]` keep/inventory previewer hooks fire for her own gear (`we_spear`, `waywatcher_hat_0010`, `maidenguard_hat_0010`) — all VANILLA item keys |
| 03:54:19 | 3474 | PC-A (`11000010ef3befb`) approved by server |
| 03:54:21 | 3519 | Hot-join sync runs for PC-A |
| 03:54:39 | 3576 | `[hot-join glow replay] sent 1 cos_glow_apply entries targeted at joiner=11000010ef3befb` |
| 03:54:41 | 3674-3675 | First `[husk-wield-wrap]` + `[husk-mesh-swap probe]` for PC-A's husk; template=`one_handed_swords_template_1`, cache empty |
| 03:54:42→05:11:55 | 3678…28672 | 1,086 husk-wield events for PC-A, ALL with `cache_has_wearer=false`; PC-A only carries vanilla templates |
| 05:11:56 | 28920 | `team_previewer.lua:120: attempt to index local 'item_template' (a nil value)` — unrelated vanilla bug on session exit (post-game results screen) |

**Notably absent across the whole timeline:** any `[cos_la_apply emit]`, `[cos_la_apply recv]`, `[CACHE WRITE]`, `[husk-hat-create]`, or `mod:echo` Loremaster-warning event.

---

## 5. Hypothesis on the user's complaint

The user-reported "loremasters requirement issue" is **not the v0.9.0.14 chat warning text** firing on Lyndsey's side. That warning code did not execute. The most likely sources of the complaint are one of:

**(a) Visual symptom mis-attributed.** PC-A's husk renders with vanilla mesh because PC-A is not wearing any LA variant this session, OR PC-A is wearing one but never broadcasts it. Lyndsey sees PC-A holding a generic sword/crossbow instead of whatever Tom (PC-A operator) sees in his own first-person view, and the user labels that "loremasters requirement issue". Lyndsey's bridge is correctly idle — there is nothing for it to apply.

**(b) The complaint came from PC-A, not Lyndsey.** Lyndsey's log is squeaky-clean: no errors, no warnings, full LA prereqs satisfied. If PC-A's side is missing LA or has the bridge disabled, *PC-A* would be the one printing the v0.9.0.14 warning when receiving a `cos_la_apply` from Lyndsey — but Lyndsey is wearing only vanilla items too (the `[LA preview]` block at 03:53:37 confirms `we_spear`, `waywatcher_hat_0010` — base names, no LA suffix), so she also has nothing to emit. The user may be relaying PC-A's chat output and conflating who produced it.

**(c) The warning is from a different mod.** The phrasing "loremasters requirement issue" doesn't match our exact v0.9.0.14 string ("Loremaster's Armoury is NOT enabled …"). It's possible the user is paraphrasing or referring to LA's own internal warning (LA itself prints UI-level "Requires Loremaster's Armoury" tooltips on locked items in the inventory screen), or to a prerequisite-mod hint shown by VMF / mod_compatibility.

**Recommended next step:** Get the **PC-A** console log from the same session. Lyndsey's side has nothing to debug — the bridge is healthy, all hooks registered, glow-replay works, husk pipeline runs 1,086 times, and the chain is simply not exercised because no LA item is in flight. The "issue" likely originates from whichever peer was actually wearing the LA item (probably Tom on PC-A) and whose log will contain the actual `cos_la_apply emit` / receive failure or warning event.
