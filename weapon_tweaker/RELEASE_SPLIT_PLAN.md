# weapon_tweaker — Dev/Stable Split + Public Release Plan (DRAFT)

Status: **DRAFT for review — nothing executed yet.** Drafted 2026-06-20 from a 3-track
research pass (content inventory, split mechanics, strip approach).

Goal: take the cross-character tuning out of permanent `-dev` limbo. Ship a **public
alpha** of weapon_tweaker that contains **only confirmed-working content**, and keep a
**friends-only dev clone** where the in-progress work (the ~132 bulk-encoded ports, the
tuning tools) continues.

---

## 1. Architecture (the corrected model)

Your message said two things that can't both hold ("the clone is working-only" *and*
"the public is working-only"). Mapped onto how the strip lever actually works, the only
coherent shape — and the one matching the existing `ct`/`ct_dev` doctrine — is:

| | Workshop item | Visibility | Content | Version |
|---|---|---|---|---|
| **Public** | `weapon_tweaker` (existing, **3712896117**) | public | **stripped to confirmed-working only** | `X.Y.Z-alpha` |
| **Dev** | `weapon_tweaker_dev` (**NEW item**) | friends-only | **full current content** (everything, incl. all in-progress ports + tuning tools) | `X.Y.Z-dev` |

> **The lever that makes this cheap:** `weapon_unlock_map` (`wt_unlock_data.lua:44`) is the
> single source of truth. A port is wieldable only if its key is in that map *and* its
> toggle is on; the dev anim-picker reads the **same file** via `mod:dofile`. So curating
> that one table down to the confirmed set strips the public build's unlock gate **and**
> its picker catalog at once — no second copy to keep in sync.

### DECISION 1 — dev clone content: **full** (recommended) vs working-only
The recommendation is **full**: the new `weapon_tweaker_dev` is a complete copy of today's
wt so none of the 132 bulk-encoded ports or the picker/hold-pose tooling is lost, and
active tuning continues there. The public item is the strict subset. This is the inverse of
"the clone is working-only" — please confirm before any stripping.

### DECISION 2 — public release track: **alpha** (recommended) vs beta
Recommend **alpha**: the public build ships only the confirmed slice while the bulk of
cross-character ports stay in dev, so it's stable-core but feature-*incomplete* — that's
alpha. Beta implies near-feature-complete, which it isn't yet. Suggested version string:
`0.13.0-alpha` (new minor signals the public milestone; `-alpha` is the track suffix).

### DECISION 3 — dev tooling in the public build: **remove** (recommended) vs leave-gated
The anim-picker is already gated off by default (zero runtime cost when off), so leaving it
is *safe*. But cleaner to **remove** `wt_dev_anim_picker.lua` + `wt_dev_hold_pose.lua` (and
their data/loc/command wiring) from the public clone — public users have no tuning surface,
and it guarantees no in-progress port labels can ever surface to subscribers.

---

## 2. Content split (what lands where)

**Public alpha — confirmed-working (~37 ports + core features):**
- Core engine (ships in both): 3P anim-remap engine (`_anim_redirect`/`_career_anim_redirect`/
  `_suffix_career_map`), the hand-curated `_WIELD_ANIM_CAREER_3P_PATCHES`, scale/grip overrides,
  the 3 flagship model subs (brace/repeater→Repeater Handgun, longbow→Crossbow), and the
  v0.12.128 anim-variable **crash guard** (load-bearing safety net — must ship).
- Confirmed ports: the ANIMATION_COVERAGE.md ✅ rows + the four `[Working]` picker tags
  (`we_1h_sword`, `dr_2h_axe`, `es_longbow`, `bw_1h_flail_flaming`) + the long-shipped
  flagship Kruber/Kerillian/Saltzpyre ports (brace, longbow, elf-spear/greatsword, billhook,
  crowbill, etc.). Default-true native unlocks stay (1P access is universal/stable).
- Opt-in extras (default OFF, low risk): `weapon_overrides` group, adventure trait toggles.
- **Hide in public:** Big Rebalance group (permanently inert since `bt` retired — keep code,
  hide the widgets) and the `cw_*` trait toggles unless `crafting_in_modded` is present.

**Dev-only (held in `weapon_tweaker_dev`):**
- The ~132 bulk-encoded ports (`_WIELD_ANIM_CAREER_3P_PATCHES_BULK`, verified-vs-vanilla but
  NOT in-game confirmed) and every `[Untested]`/`[Not Working 3rd Person]`/`[Inventory Model
  Error]`/`[Needs *]` port.
- The 7-item Wave-3 model-substitute queue (Griffon-foot, shortbow→volley-crossbow, shield
  off-hand dispatcher, etc. — all decided, none wired).
- The dev tooling: anim-picker + hold-pose tuner + `/wt_dump_*` commands.

⚠️ One reconciliation TODO before trusting the allow-list: `bw_1h_flail_flaming` is tagged
`[Working]` in the picker but `wired-unverified` in COVERAGE.md — confirm which is right.

---

## 3. Strip mechanism (public side)

1. **Curate `weapon_unlock_map`** (`wt_unlock_data.lua`, ~14 career arrays): drop every key
   that isn't in the confirmed set. This is the only *mandatory* edit. ~45–60 min.
2. **Cosmetic cleanup (recommended):** delete the now-dead `unlock_<career>_<weapon>`
   checkboxes (`weapon_tweaker_data.lua`) + matching loc keys (`weapon_tweaker_localization.lua`)
   for dropped ports, so the public Mod Options menu shows no toggles for absent ports.
   (Functionally dead if left — the main loop only queries keys that are in the map — so this
   is polish, not correctness.)
3. **Leave alone:** `_WIELD_ANIM_CAREER_3P_PATCHES[_BULK]`, `_weapon_grip_offsets`,
   `_weapon_scale_overrides` — keyed by template/weapon, they harmlessly no-op for weapons that
   are never wieldable. (Optional: trim `_BULK` for cleanliness — low priority.)
4. **Remove dev tooling** (per Decision 3): drop the two `wt_dev_*` modules + their wiring.
5. Normalize `MOD_VERSION` → `0.13.0-alpha`, keep `published_id = 3712896117` unchanged.

**`cwv_managed` is being REMOVED** (Issue #368, 2026-07-05): wt and CWV now operate
independently (overlap allowed), so wt no longer cedes `wh_1h_falchion`/`wh_dual_wield_axe_falchion`
on Kruber to CWV. Instead wt is the availability control surface — its per-weapon toggles default
ON when CWV is installed and also cover CWV's items. See `CROSS_MOD_ARCHITECTURE.md`. (The earlier
"stays as-is" plan here is superseded.)

---

## 4. Dev-clone mechanics (mirror ct/ct_dev exactly)

Create `weapon_tweaker_dev/` as a **full copy** of `weapon_tweaker/` source, then:

1. **Don't copy build junk:** exclude `bundleV2/` (regenerated by build), `*.processed`,
   `*.new`, `*.bak.*`.
2. **Rename id-bearing paths:** `weapon_tweaker.mod`→`weapon_tweaker_dev.mod`;
   `resource_packages/weapon_tweaker/`→`/weapon_tweaker_dev/` (+ the `.package` file);
   `scripts/mods/weapon_tweaker/`→`/weapon_tweaker_dev/` (+ the 3 entry files
   `weapon_tweaker[_data][_localization].lua` → `*_dev*`).
3. **`.mod`:** `new_mod("wt_dev", {...})` with all three script/data/loc paths + the package
   path re-pointed to the `weapon_tweaker_dev` tree.
4. **`.package`:** `mod`/`package`/`lua` arrays → `weapon_tweaker_dev` paths.
5. **Re-point `get_mod("wt")` → `get_mod("wt_dev")`** in all 12 cloned `.lua` files. **GOTCHA:**
   `wt_dev_anim_picker.lua:~824` hardcodes `Application.user_setting("mods_settings", "wt",
   "enable_dev_anim_picker")` — must become `"wt_dev"` or the dev mod reads the stable mod's
   saved picker toggle.
6. **`itemV2.cfg`:** `published_id = 0L;` (the **first-publish sentinel** — not omitted, not a
   real id), `visibility = "friends_only"`, title base `"Tweaker: Weapons (Dev)"`,
   `content = "bundleV2"`.
7. **Build:** `VMBLauncher.exe build weapon_tweaker_dev`.
8. **First upload (creates the item):** `VMBLauncher.exe upload weapon_tweaker_dev` (friends-only
   → **NO `--allow-public`**). Launcher writes the real `published_id` back to the cfg on
   success. On *failure* it still creates an orphan item without writing the id back — capture
   the signed `publisher_id` from stdout, `+2^32`, hand-write `published_id=<unsigned>L;` before
   any retry (else a second orphan).
9. **Subscribe** to the new item so Steam downloads it → `deploy weapon_tweaker_dev` works
   thereafter.
10. **Record the id:** add `weapon_tweaker_dev` to `qa/check_published_ids.ps1` `$Canonical` +
    `qa/PUBLISHED_IDS.md` **in the same commit**; run `qa/check_published_ids.ps1` → must PASS.
11. **(Optional)** `upload_wt_dev.ps1` wrapper (friends-only guard, no `--allow-public`).
12. `publish-release.ps1` after each upload (both streams) for vt2-mod-updater sync.

---

## 5. Cross-mod safety (verified — nothing breaks)

- The **only** runtime external consumer of wt is CWV's `get_mod("wt")` at
  `character_weapon_variants.lua:6207` (optional companion detection). It targets stable `"wt"`
  and **must keep doing so** — do not re-point it to `wt_dev`.
- `general_tweaker`'s lobby known-mods table (`["wt"]="R"`) references the stable id; stays
  correct. (Optionally add `["wt_dev"]="R"` so gt also recognizes the dev clone — not required.)
- All `cosmetics_tweaker` "weapon_tweaker" references are **code comments**, zero coupling.

---

## 6. Key gotchas (from research)

- **NEVER reuse `3712896117` for the dev cfg** — a stale/duplicated `published_id` silently
  *hijacks* the other item on upload (the 2026-06-19 gut/gt_dev incident). Dev gets a brand-new id.
- **Dev stays `friends_only` forever** — never `--allow-public`.
- **Per-mod-id isolation:** wt hooks networked anim events; wt and wt_dev are separate
  registrations, so a mixed session (one peer on dev, others on stable) won't share those RPC
  channels — friends should all pin to the same stream for a session.
- **Stable upload still needs a fresh per-build ship signal** — the "dev versions auto-upload"
  rule covers `-dev`-versioned items; the public `-alpha` stable item needs explicit approval.
- Hot-reload unsafe (full restart to test, both streams).

---

## 7. Promotion workflow (going forward)

Dev-only-edit doctrine governs: **all** new port work lands in `weapon_tweaker_dev/` only.
Public `weapon_tweaker/` is read-only between releases. When a dev port flips to ✅/`[Working]`
and you sign off, promotion = copy that port's keys from dev's `weapon_unlock_map` (+ its
checkbox/loc/wield rows) into public, bump public `MOD_VERSION`, upload via `upload_wt.ps1`
(`--allow-public`) with a fresh ship signal. **ANIMATION_COVERAGE.md's ✅ rows are the public
allow-list** — promotion is mechanical, not judgment.

---

## 8. Effort: ~2–4 hours

Clone + rename + repoint (~30m) · new Workshop item + id recording (~15m) · curate
`weapon_unlock_map` (~45–60m) · dead checkbox/loc cleanup (~45m, deferrable) · remove dev
tooling from public (~20m) · build/deploy/verify both (~30m).

---

## Decisions needed before execution
1. **Dev clone content:** full (recommended) or working-only?
2. **Public track:** `-alpha` (recommended) or `-beta`? Version `0.13.0-alpha`?
3. **Dev tooling in public:** remove (recommended) or leave gated-off?
4. Reconcile `bw_1h_flail_flaming` status (`[Working]` vs COVERAGE `wired-unverified`).
