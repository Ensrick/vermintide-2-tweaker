# PROJECT_STANDARDS.md

Operational rules for working on the Vermintide 2 Tweaker monorepo with Claude.
Authored 2026-05-22 after the v0.9.8.x cosmetics regression chain + the audit
sweep that found ~30 pending items across stale audit markdowns.

**This document is binding on Claude.** When working in this repo, follow these
rules unless the user explicitly overrides one for a specific task. When in
doubt, cite the section number you're applying.

Cross-reference: `CLAUDE.md` (technical) describes HOW things work. This doc
(`PROJECT_STANDARDS.md`) describes HOW WE WORK on them.

---

## 1. Current state assessment (baseline)

### What's working
- **CHANGELOG-per-mod discipline** is load-bearing for future-me catching up.
- **Memory file system** (`~/.claude/projects/...`) actively prevents re-burning
  recurring bug classes (forward refs, peer-sync drift, etc).
- **VMBLauncher** is engineered properly — hash verification, exit codes,
  remote PC-B deploy. Don't bypass it.
- **Per-mod data + localization separation** is canonical VMF and well followed.
- **QA tooling in place** — `luacheck` + GHA workflow + 6 PowerShell checks
  catch the recurring bug classes that previously slipped through (forward
  refs, unescaped `%`, `tags=[]`, MOD_VERSION drift, oversized files, stale
  audit docs). See §11a for the full table.

### What's still weak
- **File sizes exceed Claude's effective working memory.** 8 lua files remain
  over the 2500-line hard limit (`character_weapon_variants.lua` at ~8800,
  `chaos_wastes_tweaker.lua` at ~6100, `cosmetics_tweaker.lua` at ~6000, plus
  five others). Reading the worst offenders consumes ~80K tokens. Tracked
  under GitHub Issue #2.
- **Logging conventions inconsistent.** The prefix convention in §3.1 is only
  partially adopted across mods. No central enforcement yet.
- **Error handling has tended toward reactive layering.** The v0.9.8.x chain
  (4 patches in 24h, each fixing the prior patch's side effect) is the
  canonical example. §4.4 codifies the corrective rule; the pattern still
  recurs on hot mods if nobody catches it during review.

---

## 2. File structure standards

### 2.1 Maximum file size
- **Target**: 1500 lines per file.
- **Hard limit**: 2500 lines. When approaching, split before adding more.
- **Exemption**: pure data files (`_cosmetic_unlocks.lua`, etc.) can be larger.
- **Current violations**: tracked under GitHub Issue #2. Run
  `.\qa\check_file_sizes.ps1` for the live list. Splits happen opportunistically
  when a natural feature boundary surfaces — not Claude's job per-session unless
  asked.

### 2.2 Module layout per mod
Every mod should have:
- `<mod>.lua` — entry point + top-level hooks. Keep ≤1500 lines.
- `<mod>_data.lua` — VMF widget tree.
- `<mod>_localization.lua` — localized strings.
- Per-feature files: `_<feature>.lua` for non-trivial subsystems.

Per-feature files **must** start with a docstring header:
```lua
-- _<feature>.lua — <one-line purpose>
--
-- <2-5 sentences on what this file owns, what it depends on, and any
-- non-obvious invariants. Reference CHANGELOG entries for major design
-- decisions.>
--
-- Owned by: <mod>.lua entry point. Consumed via: <require path / mod:dofile>
```

### 2.3 When to split
Trigger a split when ANY of:
- File hits 2500 lines.
- Adding a feature would push it past that.
- A natural feature boundary lets you carve out 500+ contiguous lines.
- A subagent says "I had to re-read the whole file three times to answer this"
  — that's a context-cost smell.

---

## 3. Logging standards

### 3.1 Prefix convention
Every log line **must** start with `[<mod_id>:<feature>]`. Examples:
- `[ct:populate_pickups] level=morris_mission_03 ...`
- `[cosmetics:husk-hat-create] wearer=X armoury_key=Y ...`
- `[wt:anim-remap] career=es_questingknight key=es_axe ...`

`mod_id` is the short id (`ct`, `wt`, `cosmetics`, etc.). `feature` is a
load-bearing identifier — match what's grep'able after a crash.

### 3.2 Level discipline
- **`mod:info`** — normal flow events. Equipment changes, hooks firing,
  RPC sends. Should be safe to leave on during normal play.
- **`mod:warning`** — a guard fired and we recovered. pcall caught something.
  Vanilla returned an unexpected shape. Defensive bail with a fallback.
- **`mod:error`** — unrecovered. Crash imminent or already happened. Someone
  needs to look at this. Should be rare.
- **`mod:echo`** — user-visible chat. Only for things the player needs to see
  (mod-loaded banner, command output, error popups). Never use for debug.

### 3.3 What NOT to log
- Per-frame events (60+ Hz). Use a sample gate or move to `mod:info` only on
  state change.
- Anything that requires a verbose toggle to be useful — make it useful or
  delete it.

### 3.4 Required logging for new hooks
When you add a new `mod:hook(...)`, you must also add either:
- An `info`-level entry log on the happy path (with prefix), OR
- A `warning`-level log on every guard / bail path.

Reason: silent hooks become invisible regressions. If a feature stops working,
the log should say so.

### 3.5 Diagnostic commands
Every mod with non-trivial state should expose a `/<mod_id>_diag` chat command
that dumps current state in a copy-pasteable form. Examples:
- `/ct_diag` — current pool overrides, active mutators, altar config.
- `/cosmetics_diag` — la_equips_by_peer, offhand_selection, glow runtime.

### 3.6 Debug logging — VMF-native, no per-mod toggle (current policy 2026-06-29)

> **CURRENT POLICY (established 2026-06-29, supersedes the 2026-05-25 per-mod
> toggle below).** We do **NOT** ship our own `enable_debug_logging` checkbox
> anymore — it is redundant with VMF's own logging controls. Diagnostics route
> through VMF's logging methods and are gated by VMF's logging output level,
> which the user sets ONCE in VMF's options. There is **no per-mod toggle to
> enable/disable on our mods** — that is superfluous.
>
> - **Routine diagnostics** use the two file-local helpers, which now call VMF's
>   severity-scoped log methods directly (no `mod:get` gate of our own):
>   - `_dbg(fmt, ...)` → `mod:debug(...)` — emits only when VMF's **debug** log
>     level is on. File only.
>   - `_dbg_alert(fmt, ...)` → `mod:warning(...)` — emits only when VMF's
>     **warning** log level is on. File AND in-game chat.
>   So "as long as VMF logging is on, it happens" — specifically, `_dbg` rides
>   VMF's debug channel and `_dbg_alert` rides VMF's warning channel. The user
>   never touches a toggle on OUR side.
>   **CAUTION (Issue #240, 2026-07-02):** because VMF defaults `warning` to
>   mode 3 (`send_to_chat = mode >= 2`, upstream `logging.lua`
>   `load_logging_settings()`), a `mod:warning`-routed alert helper posts to
>   CHAT, not just the log. That is acceptable ONLY for genuine anomalies.
>   Routine diagnostics (plateau notices, expected boot-timing states,
>   consequences of the user's own slider values) must NOT route through it —
>   et's roaming-plateau line spammed chat on every mission load. et
>   (v0.7.25-dev) now routes `_dbg_alert`/`_spawn_dbg_alert` through
>   pcall-guarded log-only raw `printf` instead; see
>   `docs/BUG_CLASSES.md § 17 Variant B` for the fix template. `ct_dev`
>   still carries the chat-visible routing (fold into #169's sweep).
> - **Critical always-on telemetry** (instrumentation that MUST be captured even
>   when the user runs with VMF logging off — e.g. ct's `[ct-spawn-tally]` /
>   `[populate_pickups]` Horn-of-Magnus census) uses **raw `printf`**, which
>   bypasses ALL toggles (VMF's included) and always lands in `console_logs\`.
>   Reserve this for load-bearing diagnostics, not routine noise.
> - **Reference implementation:** `chaos_wastes_tweaker_dev` (#169, v0.7.186-dev).
>   `_dbg`/`_dbg_alert` route through `mod:debug`/`mod:warning`; zero live reads
>   of any `enable_debug_logging` key; no menu widget.
>
> **Migration status (2026-06-29).** Only `ct_dev` is fully VMF-native. Still on
> the legacy per-mod gate: `chaos_wastes_tweaker` (stable), `character_weapon_variants`,
> `general_tweaker_dev` (gate the helper on the legacy key in code, no menu
> widget); `weapon_tweaker`, `weapon_tweaker_dev`, `weapons_of_chaos` (still
> expose the menu checkbox). Rolling the VMF-native pattern out to these is a
> per-mod task — do it when touching each mod, or as a deliberate sweep.

---

#### Legacy: per-mod Debug Logging toggle (2026-05-25 — being phased out)

> Retained for the not-yet-migrated mods above. Do NOT add this to new mods or
> to `ct_dev`. New work follows the VMF-native policy above.

Established 2026-05-25. User feedback: "VMF menu options for debug are
inconsistent. Just a toggle for Debug Logging at the BOTTOM and have one
available for every single mod I have."

Each legacy (unmigrated) mod exposes a single VMF widget with **exactly** these
properties:

| Field | Value |
|---|---|
| `setting_id` | `enable_debug_logging` (verbatim — no per-mod prefix) |
| Widget type | `checkbox` |
| `default_value` | `false` |
| Localization (en) | `"Debug Logging"` |
| Tooltip (en) | `"Emit detailed diagnostic logs to %%APPDATA%%\\Fatshark\\Vermintide 2\\console_logs\\. Increases log volume; enable when investigating a bug, then disable."` (note `%%APPDATA%%` — every literal `%` MUST be doubled because VMF runs the value through `string.format`; see `LOCALIZATION_STANDARD.md` § 1) |
| Position | At the **BOTTOM of the widget tree**, as a **direct child of the top-level `mod.options_widgets`**. NOT nested inside any `group` / `Advanced` / `Misc` / `Developer` heading. |

**Anti-patterns:**
- Don't use a per-mod prefix on the setting_id (NOT `wt_enable_debug_logging`,
  NOT `cwv_debug_mode`). Same key everywhere.
- Don't nest it inside a group widget. Top-level only.
- Don't add it under "Advanced" / "Misc" / "Developer" group headings.

**Wiring (every `<mod>.lua` exposes a file-local `_dbg` helper near the top):**

```lua
local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[%s:dbg] " .. fmt, "<mod_id>", ...)
    end
end
```

If the mod already has a `_dbg` / `_log` / `mod:debug` helper under a different
gate name (`debug_mode`, `wt_debug_mode`, `cwv_debug_mode`, `debug_dumps`,
`debug`), the helper body must be renormalized to read
`mod:get("enable_debug_logging")`. Don't break existing call sites — the gate
key changes, the helper signature and call sites stay the same.

### 3.7 Debug mode is a DATA HARNESS (established 2026-06-11)

User directive: *"when the debug mode is active, every mod with it on should be
gathering any data that is not in the game's source code and is not available
via other mods I have available. I don't want to have to do a lot of digging or
scraping for data."*

**Why:** Claude cannot see the running game, and the decompiled source lacks
runtime-resolved data (skeleton anim-event vocabularies, resolved material
slots, live table contents after DLC/mod merging, unit↔backend-id maps). Every
time that data is missing, the user pays a full in-game session to fetch it by
hand. Debug Logging ON = the user is granting a data-collection window — use it.

**Rules:**

1. **Probe-first development.** When designing any feature that depends on
   runtime data, ship the probe/dump in the build BEFORE (or with) the feature
   scaffold, have the user run one session, then build on captured data — never
   on guesses. (Sibling of §14a and the diagnose-before-mitigating rule.)
2. **Dumps are parseable, not prose.** Probe output is either (a) paste-ready
   Lua in the EXACT table syntax of the destination source file (the
   `/wt_dump_anim_picks` pattern — `local _PORT_WIELD_3P = {...}` blocks), or
   (b) one-line `key=value` records greppable by a stable prefix tag
   (`[illusion-probe]`, `[wt:dev_anim]`). Never multi-line free text.
3. **Opportunistic capture is encouraged** when it's data-not-in-source and
   cheap: low-volume always-on probes (≤1 line per user action — the
   cosmetics `[illusion-probe]` precedent) may even stay UNGATED; anything
   chattier rides the `enable_debug_logging` gate.
4. **Tune→export→bake loop.** Any in-game tuning surface (anim picker, hold
   pose, glow sliders, scale/grip) MUST pair with an export command that
   serializes the user's current tuned values as paste-ready Lua. Tuning UIs
   without an export path strand the data in the session.
5. **Index your probes.** Each mod's CHANGELOG/DEVELOPMENT notes which probe
   tags exist and what they capture, so a later session greps the log instead
   of re-deriving.

**Migration:** when renaming an old key, leave a brief CHANGELOG note that the
old key (`wt_debug_mode`, etc.) was renamed and users may need to re-toggle the
new `Debug Logging` checkbox after first load. Don't try to silently auto-
migrate the saved value — the friction is one re-tick.

Cross-ref: `VMF_RECIPES.md` § 9. For Layer 3 `mod:traced_hook` (shipped in `weapon_tweaker` v0.12.84-dev), which emits structured `[<mod>:trace] event=enter|exit class=<C> method=<m> n_args=N` / `n_returned=M` log lines gated on this same `enable_debug_logging` toggle, see `VMF_RECIPES.md` § 2b "Layer 3: traced_hook" — including the per-frame rate-limit caveat.

#### Two-channel discipline (`_dbg` vs `_dbg_alert`)

Established 2026-05-25. User feedback: "When debug logging is on, I want
messages to be consistent for each mod, and show up in the in-game chat log
via echo whenever something is unexpected or wrong. If things go as expected
or just to confirm things are working or firing, I want log messages in the
actual log, not the ingame chat log. Likewise info dumps and such go into
the game log, not the in-game log."

Every mod ships **two** debug helpers (not one), both gated on the same
`enable_debug_logging` key:

**Decision matrix:**

| Case | Helper | Lands in |
|---|---|---|
| Confirmation / dump / expected behavior | `_dbg` | log file only |
| Unexpected / wrong / mismatch / error condition | `_dbg_alert` | log file AND in-game chat |
| User-operational (chat command reply, `/verify_*` output) | bare `mod:echo` | chat (not gated) |
| Permanent operational log (`[wt] enabled vX.Y.Z`) | bare `mod:info` | log file (not gated) |
| Stricter VMF levels | `mod:warning` / `mod:error` | VMF default semantics |

**Canonical helper pair** (insert near top of every `<mod>/scripts/mods/<mod>/<mod>.lua`):

```lua
-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both gate on `enable_debug_logging`. Both no-op when toggle is off.
-- `_dbg` is for confirmation / expected behavior — file only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — file AND in-game chat.
local function _dbg(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[<mod_id>:dbg] " .. fmt, ...)
    end
end

local function _dbg_alert(fmt, ...)
    if mod:get("enable_debug_logging") then
        mod:info("[<mod_id>:dbg] " .. fmt, ...)
        mod:echo("[<mod_id>] " .. fmt, ...)
    end
end
```

Replace `<mod_id>` with the mod's short ID (`wt`, `ct`, `gt`, `cwv`, `cosmetics`,
`cim`, `bt`, etc.) — match the existing log prefix convention. The mod's
`_RT_CHECKS` regression scaffold must include the smoke test:

```lua
_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local saved = mod:get("enable_debug_logging")
    if saved ~= false then mod:set("enable_debug_logging", false) end
    local ok = pcall(_dbg, "smoke test off")
    if not ok then return "_dbg raised with toggle off" end
    ok = pcall(_dbg_alert, "smoke test off")
    if not ok then return "_dbg_alert raised with toggle off" end
    if saved == true then mod:set("enable_debug_logging", true) end
end)
```

**Classifying call sites:**

When picking between `_dbg` and `_dbg_alert` for a new call site, look at the
format string + context:

- Words/phrases suggesting an **ALERT** (`_dbg_alert`):
  "failed", "error", "unexpected", "missing", "nil", "mismatch", "raised",
  "skipped", "dropped", "fallback", "corrupt", "stale", "couldn't",
  "no longer", "broken", "invalid"
- Words/phrases suggesting **CONFIRMATION** (`_dbg`):
  "fired", "applied", "installed", "registered", "loaded", "completed",
  "ok", "ready", "received", "sent", "match", "found"
- Ambiguous → leave as `_dbg`. **Conservative default.**

**Edge cases:**

- **Expected guard / SKIP branches** — even if the format string says "nil"
  or "no X", if the branch is the normal-flow exit when a guard condition
  is unmet (e.g. `if not local_player then _dbg("no local player"); return end`),
  keep as `_dbg`. Promoting it would spam chat during normal play.
- **Hot-path observation hooks** — state machine transitions, frame-by-frame
  hook entry logs, scale/grip dumps, wield events. These are confirmation,
  not alerts. `_dbg`.
- **Post-warning follow-up logs** — when a `mod:warning` has already fired
  and a follow-up `_dbg` line documents the resulting bail path,
  promote to `_dbg_alert` so the user sees the chain.

**Anti-patterns:**

- Don't use bare `mod:echo` for non-user-facing dumps — that bypasses the
  toggle and pollutes chat. Use `_dbg` (log file) or `_dbg_alert` (chat
  when toggle is on).
- Don't use `_dbg_alert` for routine confirmations — that defeats the
  whole point of the two-channel split.
- Don't introduce a third helper. Two channels (log-only, log+chat) cover
  every case in the policy matrix above.

**Cross-ref:** `VMF_RECIPES.md` § 9 (universal debug toggle).

#### Applied marker line (universal)

Established 2026-05-25 (rolled out across all 16 active mods in the same pass that added `/perf_dump` to bt). Every mod prints ONE banner-style `mod:info` line at load surfacing the current MOD_VERSION and a short hash of the live settings values, so scrolling back any `console_log-*.log` you can see exactly which build + config was running at any point.

| Field | Value |
|---|---|
| Line format | `[<mod_id>] enabled v<MOD_VERSION> settings_fp=<8-hex>` |
| Log level | `mod:info` — ALWAYS fires. Not gated on `enable_debug_logging` — this is operational telemetry, not debug noise. |
| When | Once, at load. Right after the `_dbg_alert` helper (or inside `mod.on_enabled` if the mod is togglable and the on-load surface is awkward). |
| Where to place | File-local `_settings_fingerprint()` helper near MOD_VERSION setup; the marker line directly below it. |
| Per-mod addenda | OK as trailing space-separated `key=value` tokens (e.g. et appends `host_required=true`). Keep them short. |

**Fingerprint helper** (drop-in; replace `<MOD_LONG_ID>` with the mod's directory name):

```lua
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/<MOD_LONG_ID>/<MOD_LONG_ID>_data")
    if not ok or type(data) ~= "table" then return "nodata" end
    local keys = {}
    local function walk(node)
        if type(node) ~= "table" then return end
        if type(node.setting_id) == "string" then keys[#keys + 1] = node.setting_id end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    if #keys == 0 then return "nosettings" end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do
        local v = mod:get(k)
        if v == true then       parts[i] = k .. "=1"
        elseif v == false then  parts[i] = k .. "=0"
        elseif v == nil then    parts[i] = k .. "=?"
        else                    parts[i] = k .. "=" .. tostring(v) end
    end
    local s = table.concat(parts, ";")
    -- FNV-1a 32-bit, plain-arithmetic XOR (no bit32 in Lua 5.1 sandbox).
    local h = 2166136261
    for i = 1, #s do
        local byte = string.byte(s, i)
        local xored, place = 0, 1
        local hh, bb = h, byte
        for _ = 1, 32 do
            local hb, bbit = hh % 2, bb % 2
            if hb ~= bbit then xored = xored + place end
            place = place * 2
            hh = (hh - hb) / 2
            bb = (bb - bbit) / 2
        end
        h = (xored * 16777619) % 4294967296
    end
    return string.format("%08x", h)
end

mod:info("[<mod_id>] enabled v%s settings_fp=%s", MOD_VERSION, _settings_fingerprint())
```

**Why this shape:**

- **Walks the data widget tree via `pcall(require, "...")`** rather than a hardcoded key list per mod, so the helper stays maintenance-free as `_data.lua` grows / shrinks. Cached in `package.loaded`; safe to call from main lua (already-required by VMF before main runs). Idempotent — re-evaluating the data file just rebuilds the same widget table.
- **`pcall` wrap** so a malformed / missing data file produces `nodata` instead of a hard crash on every mod load.
- **FNV-1a-32 inline** instead of a shared module — keeps the helper file-local, no resource_package additions, no cross-mod coupling. Plain-arithmetic XOR (not `bit32`/`bxor`) because VT2's Lua 5.1 sandbox doesn't ship `bit32`. Reuse the canonical implementation from `enemy_tweaker.lua:_fnv1a32` if a mod already has it (et does — its helper became the prototype for this convention).
- **Sorted keys** so the hash is deterministic across peers when settings match. Different config → different fp → mismatch visible at a glance.
- **`mod:get(k)`** at fingerprint time — captures the LIVE setting value on this peer (post any `_strip_*_widgets` mutation in `_data.lua`, like wt's CIM-conditional strip), not just the canonical definition.

**Anti-patterns:**

- Don't gate the marker on `enable_debug_logging` — it MUST always fire so logs are self-documenting.
- Don't walk `widget_definitions` or VMF internals — the simple recursive walk of the returned data table works for every shape used in this repo.
- Don't hardcode `_BR_SETTING_NAMES`-style key lists per mod for the universal marker. That pattern is fine for feature-specific RPC compares (et's `_br_settings_fingerprint` still uses it because the BR cross-peer RPC needs a stable subset), but the universal marker hashes everything.
- Don't include the master toggle in a per-mod addendum if it's already in the hashed key set — the fingerprint already changes when the master flips. Addenda are for fields that AREN'T in the widget tree (et's `host_required=true` is a static design-intent token).
- Don't print this line more than once per mod load.

**Cross-ref:** `VMF_RECIPES.md` § 11 (Per-hook perf timing via bt.perf_record — sibling experimental hardening that landed in the same pass).

#### Chat-echo policy (when is `mod:echo` allowed?)

Established 2026-05-25. User feedback: *"on enabling debug logging, I'm getting needless echos to the chat that it's enabled, this is inconsistent... on startup before enabling debug logging, I'm getting things echo'd to the chat for CWV, and I don't see the need."*

`mod:echo` writes to the in-game chat log and is **always visible to the player**. Use it sparingly. The decision matrix below is binding.

| Call site | Policy | Why |
|---|---|---|
| Module load (top of `<mod>.lua`) -- stable (>=1.0.0) versions | **NEVER** | The applied marker `[<mod>] enabled v<X> settings_fp=<hash>` line already lands in the console log; chat banner is pure spam. |
| Module load (top of `<mod>.lua`) -- dev / alpha / beta / rc / 0.x versions | **REQUIRED** -- one line, `[<mod_id>] v<MOD_VERSION> loaded` (see snippet below) | Established 2026-05-25 EOD: in-flight builds change patch-by-patch and the user needs the active version visible at a glance. Silent dev banners feel like errors are being hidden. Cross-ref § 14a persistence-after-fix protocol. The applied marker is log-only and not enough for live iteration. |
| `mod.on_setting_changed` for routine settings | **NEVER** | Spams chat on every checkbox flip — including the universal `enable_debug_logging` toggle, which is what triggered this policy. Use `_dbg` if you need a trace. |
| `mod.on_setting_changed` for explicit high-impact toggles | **OK** | Operational feedback the user expects in response to a deliberate action. Canonical examples: `bt`'s `bt_master_enable_br_registrations` ("can't apply yet — restart" / "master toggled OFF") at `buff_tweaker.lua:~275`; `gt`'s AI takeover toggle ("AI ON / OFF requested") at `general_tweaker.lua:~826-828`. |
| `mod.on_enabled` echoing version / banner | **NEVER** | Same reasoning as module load — the applied marker line covers it. |
| `mod.on_enabled` / `mod.on_disabled` for non-trivial state changes | **OK** | When the user toggles the whole mod off/on via the VMF menu, immediate chat confirmation of what unwound (or didn't) is high-impact operational feedback. Canonical examples: `enemy`'s "Enemy Tweaker enabled / disabled — compositions restored" at `enemy_tweaker.lua:~929/949`; `gt`'s `on_disabled` "Disable does not fully unwind active mutations" warning at `general_tweaker.lua:~849` (this is the canonical Issue #15 documented-limitation pattern from `docs/BUG_CLASSES.md § 7`). |
| Inside `mod:command(...)` bodies (`/verify_*`, `/<mod>_regression_test`, `/dump`, status commands, etc.) | **OK** | User invoked the command via chat; reply belongs in chat. Don't gate these on `enable_debug_logging`. |
| Routine confirmations / diagnostic traces | **NEVER bare `mod:echo`** — and NEVER `mod:warning` either | Use `_dbg` (debug channel, log-only) or a log-only printf helper. `mod:warning` posts to CHAT under VMF default settings (Issue #240; `BUG_CLASSES.md § 17 Variant B`). |
| Unexpected guard / fallback recovery | `_dbg_alert` (or `mod:warning`) | Per two-channel discipline. NB: `mod:warning` lands in chat whenever VMF's warning channel is chat-enabled — which is the DEFAULT (mode 3), not only when debug logging is on. Acceptable for genuine anomalies; et routes its alert helpers through log-only printf instead (#240). |

**Canonical dev-banner snippet** (drop right after the `mod:info("[<mod_id>] enabled v%s settings_fp=%s", ...)` applied marker line in every mod's main lua):

```lua
-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[<mod_id>] v%s loaded", MOD_VERSION))
end
```

Replace `<mod_id>` with the canonical short id (bt / crt / ct / cwv / cosmetics / cim / dcp / et / ewt / gt / gut / mp / wt). The `^0%.` branch catches versions like `0.1.12` (no track suffix) so dcp and other 0.x stable-looking versions still print. Bump to 1.0.0+ to flip a mod to silent-on-load — no other change needed; the detector matches no branches and the `if` falls through.

**Anti-patterns:**
- Don't add a debug-gated `if mod:get("enable_debug_logging") then mod:echo(version) end` — the dev-banner above already runs unconditionally for dev/alpha/beta/0.x and is silent for stable. Gating on debug-logging is the wrong axis.
- Don't add new `mod:echo` in any hook body without confirming the call site appears in the OK column above. New chat echoes are a code-review red flag.
- Don't downgrade an OK echo to `_dbg` just because the policy mentions `_dbg`. The matrix is exhaustive — if the call site is in an OK row, keep the bare `mod:echo`.
- Don't echo more than one banner per module load — one line is enough. The applied-marker `mod:info` line above stays unchanged and remains log-only.

**Verification:** before shipping any mod, `Grep mod:echo <mod>/scripts/mods/<mod>/<mod>.lua` and audit each hit against the matrix. Per `docs/BUG_CLASSES.md § 17 "Chat-echo spam"` for the failure-mode catalogue.

---

## 4. Error handling standards

### 4.1 pcall discipline
Every hook on a vanilla method that could crash the game **must** pcall-wrap
the inner call if the wrap is non-trivial:
```lua
mod:hook("SomeClass", "some_method", function(func, self, ...)
    -- Setup / pre-mutation
    local ok, result = pcall(func, self, ...)
    -- Restore / post-mutation
    if not ok then
        mod:warning("[mod:feature] inner errored: %s — bailing", tostring(result))
        return
    end
    return result
end)
```

Trivial passthroughs (`return func(self, ...)`) don't need pcall.

### 4.2 The "guard ≠ bail" rule
**A hook that returns without calling `func` is NOT a no-op — it removes
vanilla's mutation.** Before adding a guard with an early return, ask:
- What state mutation does vanilla normally do here?
- Will skipping that mutation leave the system inconsistent?

If yes, the guard is wrong. Either let vanilla run, or do vanilla's mutation
yourself, or document the consequence loudly.

Reference: v0.9.8.3 cosmetics_tweaker skeleton precheck bailed without calling
vanilla → husk never got hat attachment → user reported "no helmet at all."
Captured in memory.

### 4.3 Document failure modes
When adding a defensive guard, the comment must include:
- **What failure mode** this prevents (crash type, log signature, repro steps).
- **Citation**: CHANGELOG version, crash GUID, or memory file reference.
- **Why this is the right shape** (vs alternatives).

Bad:
```lua
-- defensive guard
if not unit then return end
```

Good:
```lua
-- v0.7.84 sanity guard: vanilla rpc_create_attachment can arrive before
-- unit is fully initialized. Crash GUID a31bc963 (2026-05-22): nil
-- _attachments table indexed at attachment_utils.lua:52. Bailing here
-- lets vanilla retry on the next RPC.
if not unit then return end
```

### 4.4 Don't stack speculative defenses
If a fix introduces a NEW bug (e.g. v0.9.8.3 → v0.9.8.4 → v0.9.8.6 → v0.9.8.7),
**revert all of them and find the actual root cause** before adding any guards.
Speculative-defense stacking is the dominant regression pattern in this repo.

---

## 5. Testing & verification standards

### 5.1 Mandatory pre-ship checks
Before declaring any mod "shipped" (uploaded to Workshop), Claude must verify:
1. **`MOD_VERSION` bumped** since last upload.
2. **CHANGELOG entry** for the new version exists.
3. **Forward-reference audit**: every `local function foo` is defined before
   any caller. (Future: automate via luacheck.)
4. **No `tags = [ ]`** in cfg (per `tools/vmb-launcher/CLAUDE.md` § "Drop `tags = [ ];` from cfg on first upload").
5. **Preview file exists** at the path the cfg references.
6. **Visibility matches expectation** — never auto-flip to public.
7. **Verify-before-shipping coverage (§5.1a)** — every fix lands with an apply-site log line AND a `/verify_<feature>` chat command.

### 5.1a Verify before shipping (non-negotiable)

**Every fix to a VT2 mod ships with (a) an apply-site log line proving the path ran and (b) a `/verify_<feature>` chat command the user can run from the keep. No more "should work" fixes.** Established 2026-05-23 after repeated burns where fixes compiled, looked right, and silently did nothing in practice:

- ct v0.7.66 mutator hook on `template.server_start_function` — dead field, no behavior change shipped.
- ct v0.7.76 grudge marks hook on `add_enhancements_for_difficulty` — bypassed by upvalue captures.
- ct v0.7.88 dormant boon gate on `DeusPowerUpRarityPool` — vanilla rolls from `DeusPowerUpsArrayByRarity` instead, so the gate did nothing.

Each surfaced only in live play, often hours into a session, and required a host+client log diff to root-cause.

When writing any fix that mutates a runtime table or installs a hook:

1. **Add an apply-site log line** at the exact mutation / hook-installation. Format: `[<feature>] applied: <specific evidence>`. The log MUST contain concrete numbers / names that prove which path executed. "Applied." with no detail does NOT count. Examples:
   - `[grudge] %d marks banned: %s` after the `BossGrudgeMarks` mutation.
   - `[dormant] added %s to %s rarity pool (now %d entries)` after the pool insert.
   - `[hook-install] %s hooked at %s` after every `mod:hook` returns.

2. **Add a `/verify_<feature>` chat command** that reports the LIVE state of whatever the fix touches, compared against the toggle / setting that's supposed to gate it. Format: per-item rows showing `name | toggle_state | live_state | PASS/FAIL`. Should work from the keep where possible — read globals directly, don't depend on `Managers.state.entity`.

3. **Verify the right table.** Before gating any boon-related write, grep vanilla code (`deus_power_up_utils.lua`, `deus_run_controller.lua`, etc.) for which table is actually READ at roll/grant time. Don't gate the table that LOOKS authoritative — gate the table that vanilla's call site reads.

4. **For hook installations**, grep for `local <name> = <Class>.<method>` and `<field> = <Class>.<method>` patterns first (see `DEVELOPMENT.md` § "Upvalue capture at file load bypasses later mod:hook"). If any match exists, the hook is dead and you need to mutate data instead.

5. **CHANGELOG entries on fix-class commits** must include the verification command name in the body. Reviewer should be able to run `/verify_<feature>` and confirm before next session.

If any of these is impractical (e.g. nothing observable from the keep), say so explicitly in the changelog — but the default is full coverage.

### 5.2 Manual smoke test expectation
For changes affecting load-bearing systems (cosmetics, weapon hooks, attachment
system, network RPCs), the user is expected to do at least one in-game test
before next session. Claude should remind them and ask for the log if
something looks off.

### 5.3 Subagent pre-ship review (recommended)
For changes touching multiple files or load-bearing code, dispatch a subagent
BEFORE shipping:
- Read the diff
- Cross-reference against CHANGELOG
- Check pcall coverage
- Check no info-level logs in tight loops
- Verify MOD_VERSION bumped
- Look for regression patterns

Subagent prompt template:
> Review the recent changes to `<mod>` for ship-readiness. Read CHANGELOG entry
> for v<X.Y.Z>. Walk every modified hook, verify pcall coverage and log levels.
> Identify any new "guard ≠ bail" violations. Report: ship-ready / fix these
> first / open questions.

### 5.4 Future: automated testing
**Track item**: set up `luacheck` + GitHub Actions. Catches forward refs,
unescaped `%`, undefined variables, dead vars. ~1 hour to scaffold.

Recommended order of automation investment:
1. **`luacheck` locally** + pre-commit hook (catches forward refs, % bugs).
2. **GitHub Action** running luacheck on push (catches what slips locally).
3. **Cfg validator script** (catches tags=[], missing preview, BOM).
4. **MOD_VERSION presence check** (catches missing constants pre-publish).
5. **CHANGELOG format validator** (optional, low ROI).

---

## 6. Version & changelog standards

### 6.1 MOD_VERSION
Every mod **must** define `local MOD_VERSION = "X.Y.Z[-stage]"` near the top
of its main lua. Format:
- `X.Y.Z` — semver-ish for the mod
- `-stage` — optional: `-alpha`, `-beta`, `-dev`, `-rc<N>`. Descriptive
  suffixes (`-hotfix`, `-la-icons`) are tolerated for in-flight work but
  should be cleaned to `-alpha`/`-dev` for release-quality versions.

### 6.2 Bumping
Bump BEFORE building:
- **PATCH** (`0.7.83 → 0.7.84`): bug fixes, small features.
- **MINOR** (`0.7.84 → 0.8.0`): new user-facing features, breaking VMF setting
  renames.
- **MAJOR** (`0.8.x → 1.0.0`): explicit "stable release" milestone.

### 6.3 Workshop title sync
Per `feedback_version_in_workshop_title.md` memory: the cfg title carries
` v<MOD_VERSION>` suffix. Future: launcher auto-rewrites on upload. For now,
update by hand or accept that the title will lag.

### 6.4 CHANGELOG entry format
Per-mod `CHANGELOG.md`. Top entry first (descending chronology). Format:
```markdown
## 0.X.Y-stage (YYYY-MM-DD) — short title

### Why
<1-2 sentences on the trigger: bug report, audit finding, new feature ask>

### Changed
- file:line — summary
- file:line — summary

### Notes
- Optional: gotchas, deferred items, follow-up tasks.
```

Don't bury fixes in version "highlights" — list every meaningful change so
future-me can find it via grep.

### 6.5 Dev vs stable stream (public-Workshop mods only)

Established 2026-05-26. The four public-Workshop mods — `chaos_wastes_tweaker`
(`ct`), `crafting_in_modded` (`cim`), `general_tweaker` (`gt`),
`verminious_dreams_lighting` — are split into two parallel directories each:
`<mod>/` (stable, public Workshop) and `<mod>-dev/` (friends-only Workshop).
All other mods are single-stream and this section does not apply to them.
See `CLAUDE.md` § "Dev/stable split workflow" for the full rationale and the
Workshop ID / mod_id mapping.

**The binding rules:**

- **All new work goes in `<mod>-dev/`.** Iteration, in-flight fixes, half-done
  experiments. Never edit the stable directory directly for in-flight work —
  if a stable-bound user bug needs a hotfix, write the fix in `<mod>-dev/`
  first, verify it in the dev stream, then promote.
- **Dev MOD_VERSION carries `-dev`/`-alpha`/`-beta`/`-rc<N>`** per § 6.1. Dev
  uploads always target the friends-only item with `visibility = "friends_only"`
  in the dev clone's `itemV2.cfg`. They never use `--allow-public`.
- **Stable receives release merges only.** When a chunk of dev work is ready
  to ship to public, it gets promoted via the checklist below — never by
  editing the stable directory in parallel with dev.

**Promote-to-stable checklist** (binding when merging dev work down to stable):

1. **Cherry-pick or merge** the work into `<mod>/` from `<mod>-dev/`. Do this
   as a deliberate copy / patch — don't symlink, don't share files, don't
   build from the dev tree with a `--out=<stable>` trick. The stable tree
   must be an independent, audit-able copy of the released code.
2. **Set MOD_VERSION to the version the user names for the release** in
   `<mod>/scripts/mods/<mod>/<mod>.lua`. It MAY keep a pre-release suffix —
   a public beta/alpha on the stable item is a legitimate, user-chosen state
   (e.g. ct promoted 2026-07-03 as `0.7.130-beta`; gut stable runs as a
   public alpha). Strip the suffix only when the user names a clean version
   (then per § 6.1: `0.7.66-dev` in dev becomes `0.7.66`, or bump to
   `0.7.67` if a previous stable build already used it). The suffix carried
   here decides future ship approval per § 6.6.
3. **Update the stable mod's CHANGELOG.md** with a single rolled-up entry
   covering the merged work. Reference the dev versions that contributed
   if it helps the reader (`merge of dev 0.7.62-dev..0.7.66-dev`).
4. **`VMBLauncher.exe build <stable-mod>`** — confirm clean compile against
   the stable tree.
5. **`VMBLauncher.exe deploy <stable-mod>`** — push to PC-A + PC-B and
   smoke-test in-game from the stable bundle. The dev bundle may be live in
   the same install (different mod_id) — that's fine, but the test you're
   running here is "does the stable build behave correctly on its own".
6. **Fresh per-build ship signal from the user** (§ 5.1, § 5.1a, the
   per-build approval rule). "Ship it" from earlier in the session does NOT
   carry forward to a stable push. Stable uploads are visible to public
   subscribers irreversibly on flag — re-confirm before each push.
7. **Upload via the `upload_*.ps1` wrapper** at repo root (`upload_ct.ps1`,
   `upload_cim.ps1`, `upload_gt.ps1`, etc.) — it carries the
   visibility-regression guard on top of
   `VMBLauncher.exe upload <stable-mod> --allow-public`. Don't bypass with a
   raw `--allow-public` call.
8. **`.\tools\publish-release\publish-release.ps1`** — publishes the bundle
   to the GitHub release so `vt2-mod-updater` consumers stay in sync.
9. **`git add` / `git commit` / `git push`** the stable source + version +
   CHANGELOG changes. The source commit is PART of the ship, not a follow-up:
   uncommitted shipped work piles up silently (three sessions' worth was found
   uncommitted on 2026-07-01).

**Dev uploads are pre-authorized: NO per-build approval.** Per the ship
doctrine in § 6.6, a `-dev`/`-alpha`/`-beta`-versioned build ships the full
pipeline on every update. Dev uploads target the friends-only item, skip
`--allow-public` and the `upload_*.ps1` wrapper, and ride the `ship.ps1`
pipeline (which wraps `VMBLauncher.exe upload <mod>-dev`; the launcher's
visibility check auto-passes for `friends_only`). GitHub release AND the source
commit/push are part of every dev ship, not optional follow-ups.

**Cross-mod refs** always resolve against the stable mod_id (`get_mod("cim")`,
`get_mod("gt")`, `(get_mod('bt') or {}):is_br_active()`). Dev clones are
isolated test surfaces; no consumer mod resolves against `cim_dev`/`gt_dev`/
etc. If you need to point a consumer at a dev clone for testing, edit the
consumer's `get_mod(...)` call locally — never ship that change to a stable
directory.

**RPC isolation caveat:** anything keyed by mod_id (lobby RPC channels, the
`GT_LOBBY_RPC_SCHEMA` constant, mod-defined `network_register` channels) is
automatically isolated between stable and dev because the mod_ids differ.
Sessions that need the lobby/MOTD surface should pin every peer to the same
stream.

### 6.6 Ship doctrine: keyed off the MOD_VERSION suffix (canonical, 2026-07-01)

Whether a build ships to the Workshop without asking is decided by the
**MOD_VERSION suffix**, not by the directory, the Workshop visibility, or how
long ago the user said "ship it". This is the single source of truth for ship
approval; where earlier text conflicts, this section wins.

**Pre-release-versioned mods (`-dev` / `-alpha` / `-beta` / `-rc<N>`) cover
EVERY active mod in the repo, including single-stream PUBLIC ones like
`wt`, `cosmetics_tweaker`, `enemy`, `event`, `crt`:** every update ships the FULL pipeline
with NO per-build approval. The full pipeline is:

1. `tools\ship\ship.ps1 -Mod <name>` builds, deploys to PC-A + PC-B, uploads
   to the Workshop item, publishes the GitHub release, and verifies the deploy
   hashes plus the `workshop_log.txt` upload status. Add `-AllowPublic` when the
   mod's `itemV2.cfg` is public. Use `-NoRemote` ONLY when PC-B is unreachable,
   and say so in the report.
2. `git add` / `git commit` / `git push` the source change. The source commit
   is PART of the ship, not an optional follow-up.

Do NOT downgrade a `-dev` update to deploy-only "to be safe". For a mod the
user is subscribed to, Steam re-syncs the Workshop bundle over any local
deploy, so the upload is the ONLY path that reaches the user's game; and
uncommitted shipped work piles up silently (three sessions' worth was found
uncommitted on 2026-07-01), so the commit + push is mandatory.

**Clean-versioned stable / public promotions (no pre-release suffix, public
`ct` / `cim` / `gt` / `gut` / `verminious_dreams_lighting` at promotion):**
require a FRESH, explicit, per-build ship signal from the user that names the
version. "Ship it" said earlier does NOT carry forward. Default for these is
build + deploy only; treat the upload like `git push --force`. Full promote
checklist in § 6.5.

**Visibility is orthogonal to the suffix rule (user ruling 2026-07-04, closed
#328).** Workshop visibility (public / friends-only / private) is user-dictated
per item and carries NO ship-approval meaning: the MOD_VERSION suffix alone
decides whether a build ships without asking. A public item whose current
version carries a pre-release suffix (e.g. stable ct at `0.7.130-beta`, a
deliberate public beta) ships the full pipeline with no ask. Never infer,
"correct", or guard a visibility from the version, directory, or stream —
`-AllowPublic` is a purely mechanical flag, required whenever `itemV2.cfg`
says `public`. There is no suffix-vs-visibility contradiction to tie-break.

**Post-ship checks (both streams):**
- Confirm `Uploaded new content` in `workshop_log.txt`. `ugc_tool` prints
  "Upload finished" even when nothing transferred.
- A deploy-verify hash MISMATCH after a CONFIRMED upload is a Steam reconcile
  race, not a ship failure: do one local re-deploy, then continue.
- A self-authored upload only re-downloads after a full Steam restart (tray
  Exit, reopen); a game relaunch is not enough. Remind the user.

---

## 7. Documentation standards

Documentation in this repo falls into three categories — **canonical** (long-
lived, tracked, every reader needs them), **reference** (long-lived, tracked,
specific topics), and **ephemeral** (snapshot or in-flight work, not tracked).
The rules below codify what goes where and how each type is maintained.

### 7.1 Canonical document map

The complete list of canonical docs and where each lives.

**Repo-root canonical (every doc below is binding on Claude when working anywhere in the repo):**

| Doc | Tracked? | Purpose | Update trigger |
|---|---|---|---|
| `CLAUDE.md` | Yes | Technical entry point — how the code works | Architecture changes; new mods; new cross-mod patterns |
| `PROJECT_STANDARDS.md` (this file) | Yes | Operational rules — how WE work | New recurring pain → new rule; old rule disproven → revise |
| `LOCALIZATION_STANDARD.md` | Yes | VMF localization convention | Convention change; new pattern proven across ≥2 mods |
| `CROSS_MOD_ARCHITECTURE.md` | Yes | How mods interact at runtime (LA bridge, co-install detection) | New cross-mod surface; new bridge pattern |
| `CHANGELOG.md` (repo root) | Yes | Repo-aggregate release notes | Per-mod CHANGELOG entries that affect multiple mods or the toolchain |
| `REGRESSION_CHECKLIST.md` (repo root) | Yes | Master list of repo-wide regression signatures | New crash class survives more than one fix attempt |
| `WORK_ITEMS.md` | Yes | Current status snapshot across mods | Treat as ephemeral pointer; GitHub Issues §11 is source of truth |
| `WEAPON_CATALOG.md` / `ITEM_LIST.md` / `ANIMATION_RESEARCH.md` | Yes | Reference catalogs | When the underlying data changes (new weapon, new skeleton probe) |
| `VMF_RECIPES.md` / `COMMANDS.md` | Yes | Cross-mod reference (VMF gotchas, command inventory) | New VMF burn class; new chat command in any mod |
| `DEVELOPMENT.md` (repo root) | Yes | Historical architecture reference | Pre-dates CLAUDE.md; still authoritative for topics it covers |

**Per-mod canonical:**

| Doc | Required? | Purpose |
|---|---|---|
| `CHANGELOG.md` | **Mandatory, every mod** | Per-mod version history (§6.4 format) |
| `REGRESSION_CHECKLIST.md` | **Mandatory, every mod** | Per-mod subset of repo-wide checklist + mod-specific regressions |
| `CODE_REVIEW.md` | **Mandatory for public-Workshop mods** (`ct`, `gt`, `cosmetics_tweaker`, `verminious_dreams_lighting`); optional for friends-only | Snapshot architectural review |
| `CLAUDE.md` (per-mod) | Optional | Workflow guardrails specific to that mod (only when the mod has non-obvious gates — see `dynamic_cosmetic_portraits/CLAUDE.md`) |
| `DEVELOPMENT.md` (per-mod) | Optional | Mod-specific architecture (use when the mod has system-level docs that don't fit in the main lua's header docstring) |
| `RECIPES.md`, `<TOPIC>_PLAYBOOK.md`, `DEFINITION_OF_DONE.md` | Optional | Reference docs for recurring authoring tasks within the mod |
| `TODO.md` | **Discouraged** | Use GitHub Issues per §11 instead |
| `POSTMORTEMS.md` | Created on first incident | Rolled-up post-incident records — see §7.3 |

The "public" / "friends-only" distinction is the `visibility` field in
`itemV2.cfg`. Friends-only mods (`wt`, `crt`, `cwv`, `cim`, etc.) ship without a
public CODE_REVIEW because they aren't user-facing in the same way. The list
above pins the currently-public mods explicitly — if you change a mod's
visibility, also create/remove CODE_REVIEW.md.

### 7.2 Per-mod required structure

Every per-mod folder must have at minimum:

```
<mod>/
├── CHANGELOG.md            # §6.4 format
├── REGRESSION_CHECKLIST.md # per-mod subset of repo-wide checklist + mod-specific entries
└── (CODE_REVIEW.md if public)
```

Anything else is optional. Don't create an empty stub of an optional doc just
to satisfy "the standard" — the standard says it's optional for a reason.

### 7.3 The three-bucket model for non-canonical docs

In addition to the canonical docs above, mods accumulate three other kinds of
documentation. Each has a fixed home.

**Bucket A — Reference docs** (long-lived knowledge, tracked, mod-root):

Enduring "how-to" or "why-this-works" knowledge that a future contributor needs
to consult. Examples: `character_weapon_variants/RECIPES.md`,
`cosmetics_tweaker/LA_SYNC_MODEL.md`, `weapon_tweaker/CROSS_CHARACTER_PORT_RECIPE.md`,
`cosmetics_tweaker/VT2_NETWORKING_REFERENCE.md`.

Rules:
- Lives at the mod root, named `<TOPIC>.md` (UPPER_SNAKE_CASE).
- Tracked in git.
- Read top-to-bottom by a new reader; not append-only.
- Updated in place when the underlying knowledge changes.
- If a reference doc gets contradicted by a postmortem entry, update the
  reference; the postmortem entry is the trigger, the reference is the
  durable record.

**Bucket B — Postmortems** (`<mod>/POSTMORTEMS.md`, append-only, tracked):

When an investigation resolves (the bug is fixed, the mystery understood, the
patch shipped), the lessons get one entry in `POSTMORTEMS.md`. One file per
mod. Append-only — new entries go at the top.

Entry format:

```markdown
## YYYY-MM-DD — <symptom one-liner> (resolved v<X.Y.Z>)

**Symptom**: <what the user saw / what crashed / what log line surfaced>

**Root cause**: <the actual underlying cause, in 2-4 sentences>

**Fix**: <what shipped, with file:line citation>

**Why it took so long** (optional): <if the resolution path was non-obvious,
what the wrong hypotheses were and what evidence finally redirected>

**Future-prevention**: <what would catch this earlier next time —
a new check in qa/, a new memory entry, a new pre-ship gate>

**References**: CHANGELOG v<X.Y.Z>, memory `<name>`, GitHub #<N>
```

Rules:
- One `POSTMORTEMS.md` per mod, created on first incident.
- Tracked in git.
- Entries are immutable after they land (don't go back and rewrite — write a
  new entry pointing at the old one if understanding changes).
- A postmortem entry is the END of an investigation. Open investigations live
  in Bucket C.

**Bucket C — Active investigations** (`<mod>/_investigating/`, gitignored):

Working notes for a bug or feature currently being worked on. Multiple files
OK — name them `<short-topic>.md`. The convention is: anything in
`_investigating/` is in-flight and may be wrong.

Lifecycle:
1. Investigation starts → drop notes into `<mod>/_investigating/<topic>.md`.
2. Investigation finishes → distill key findings into one
   `POSTMORTEMS.md` entry, delete the `_investigating/` file(s).
3. If the investigation is abandoned (turned out to be unrelated, etc.), just
   delete the file — no postmortem needed.

Rules:
- The whole `_investigating/` subdir is in `.gitignore`. These notes are
  ephemeral; clones don't get them.
- Don't track these into git "just in case" — the distillation step is the
  whole point. Permanent archaeology lives in `POSTMORTEMS.md`.
- If you find yourself wanting to keep an `_investigating/` doc as a permanent
  artifact, ask: is this enduring knowledge (→ promote to Bucket A reference)
  or is it about a specific past incident (→ promote to Bucket B postmortem
  entry)? Either way, the in-flight file gets deleted.

**Migration note (2026-05-23):** The existing one-off investigation docs in
`cosmetics_tweaker/` (HOST_CLIENT_AUDIT, GLOW_HOOK_INVESTIGATION,
HUSK_HOOK_FIRING_DIAGNOSIS, LYNDSEY_v15_LOG_ANALYSIS, PCA_v15_LOG_ANALYSIS,
ROOT_CAUSE_SYNTHESIS, etc.) pre-date this standard. They are not required to
be migrated immediately. Treat them as a slow backlog: when one is referenced
during work, either distill it into a `POSTMORTEMS.md` entry then delete it,
or promote it to a permanent reference doc if it's enduring knowledge. Do not
sweep all 27 in one pass — touch them as work surfaces them.

### 7.4 Audit snapshots

Audit reports (`AUDIT_*.md` at repo root or per-mod) are a special case of
ephemeral document: they're snapshots of repo state at a point in time, not
living documents.

Rules:
- Audit reports are **gitignored** at the root (`AUDIT_*.md` pattern in
  `.gitignore`) — they're snapshots, not source of truth.
- Findings from an audit either:
  - Get filed as GitHub Issues (per §11), with the audit report as context, OR
  - Get distilled into a `POSTMORTEMS.md` entry (when the audit found a
    specific past incident's root cause), OR
  - Get rolled into a Bucket A reference doc (when the audit revealed a
    pattern worth documenting).
- The audit report itself is then deleted — its findings are now tracked
  somewhere durable.
- If you want to preserve an audit report for archaeological reasons, move it
  to `_archive/audits/YYYY-MM-DD/` and add a `> ⚠ ARCHIVED — superseded by
  <where>` banner per §7.5.

### 7.5 Supersession banner (preserved from previous version)

When a tracked doc becomes obsolete but you keep it for historical context,
mark it at the top with:

```markdown
> ⚠ SUPERSEDED — this snapshot is from <date>. Current state lives in
> <newer doc> as of <date>. Kept for historical context.
```

Do NOT silently delete obsolete tracked docs — they may be referenced from
commit messages, memory files, or external links. Banner + keep, or migrate
the content to its new home and then delete with a commit message that says
where it moved.

### 7.6 Doc creation gate (when do I make a new file?)

Before creating any new `.md` file, answer:

1. **Is this enduring knowledge or a one-time snapshot?** If snapshot, it's
   either a postmortem entry (Bucket B) or an audit (gitignored) — don't
   create a new doc, append to the existing one.
2. **Does this belong in an existing doc?** Reference docs (Bucket A) tend to
   sprawl. Check if a new section in an existing file fits before creating a
   new file. Three sections in one file beats three small files.
3. **Is this actually a GitHub Issue?** Planning docs, roadmaps,
   "we should do X" — those are Issues per §11.
4. **Is this a workflow guardrail for one mod, or general?** General → repo
   root. Mod-specific → per-mod (and only if the mod has non-obvious gates
   that won't fit in the main lua's docstring header).

If after answering 1-4 you still need a new file, create it. The bias is
against creating new files.

### 7.7 Doc maintenance trigger

Each canonical doc lists its update trigger in §7.1. In practice:

- **At ship time:** CHANGELOG entry, POSTMORTEMS.md entry if a bug got fixed.
- **At architecture change:** CLAUDE.md, CROSS_MOD_ARCHITECTURE.md as relevant.
- **At new-pattern recognition:** PROJECT_STANDARDS.md (this doc) — propose
  the rule update in the same PR as the work that revealed the new pattern.
- **At reference-knowledge drift:** Bucket A reference docs. If a recipe in
  RECIPES.md is wrong, fix it the same session you notice.

Don't run periodic "doc cleanup" passes. Update in place at the moment of
change, where the context is fresh. Periodic cleanup correlates with stale
docs because it disconnects the update from the cause.

### 7.8 Inline comments (preserved from previous version)

Comments explain **why**, not what. Bad:
```lua
-- increment i
i = i + 1
```

Good:
```lua
-- Skip the first slot (left hand) because vanilla's hand_unit_1p only
-- spawns into right-hand on careers without a shield.
i = i + 1
```

When fixing a bug, leave a citation in the comment:
```lua
-- v0.7.84: name-based identity check (was positional [1] before). Fragile
-- against FatShark array reorders; see CHANGELOG and POSTMORTEMS entry
-- 2026-05-22 for the original concern.
```

Citation targets: CHANGELOG version, POSTMORTEMS.md date, memory file name,
GitHub issue number. NOT audit-report line numbers (audits are ephemeral
per §7.4) and NOT raw line counts in long docs that will drift.

### 7.9 Filename conventions

- **All canonical/reference doc filenames are UPPER_SNAKE_CASE** with `.md`
  extension. Confirmed consistent across all 17 mods as of 2026-05-23 — no
  case drift in the repo. Maintain.
- **Investigation notes** (Bucket C) can use lowercase if you prefer; that
  subdir is gitignored and conventions there don't matter.
- **No spaces, no dashes in canonical filenames.** `CODE_REVIEW.md`, not
  `code-review.md` or `Code Review.md`.

---

## 8. Workflow standards for Claude

### 8.0 Bug-report intake

When the user opens a session with a bug report (log path + symptom), the
first read is `docs/BUG_TRIAGE_RUNBOOK.md`, not the mod source. The runbook
is the 60-second orientation: Phase 1 (log + git log + open Issues), Phase 2
(match against `docs/BUG_CLASSES.md`), Phase 3 (deep-dive log signatures),
Phase 4 (fix with apply-site log + `_rt_register` + `/verify_<feature>` +
Workshop upload + GitHub release), Phase 5 (catalog the bug class +
POSTMORTEMS entry + lint follow-up). Cross-refs every rule in this doc that
applies (§ 3.6, § 4.2, § 5.1a, § 6.4, § 7.7, § 8.1, § 8.2, § 8.3, § 8.6,
§ 9.x anti-patterns, § 11 Issues, § 15 tests).

### 8.1 Empirical-first
Before adding code:
1. Read the actual crash/symptom evidence (log, dump, repro).
2. Read the actual current code (don't trust stale audit line numbers).
3. Read vanilla source if a hook is involved.
4. Form a hypothesis grounded in observed evidence.
5. THEN code.

If you can't articulate "the failure mode is X, citation Y, fix Z", you're not
ready to ship.

### 8.2 Subagent-first for context-heavy tasks
Dispatch a subagent when ANY:
- Reading >3 files for one question.
- Need to scan a CHANGELOG with >100 entries.
- Cross-referencing audit doc + current code + git log.
- "Where is X used across the repo?" type questions.

Subagent benefits:
- Preserves main context for synthesis + decisions.
- Forces explicit prompt = explicit task scope.
- Parallel agents fan out quickly.

### 8.3 One focused change per session
Multi-fix sessions correlate with regressions in this repo's history. Default
to one feature/fix per session unless the user explicitly asks for a batch.
When batching, ship + verify each one before starting the next.

### 8.4 Pre-ship subagent review (mandatory for hot mods)
For changes to `cosmetics_tweaker`, `chaos_wastes_tweaker`, `weapon_tweaker`,
`character_weapon_variants`: dispatch a pre-ship review subagent (see §5.3).
For other mods: optional but encouraged.

### 8.5 Defensive subagent for "is this still true?"
When a memory or audit references "current code does X at line Y": verify
before acting. Memory cited claims can be 20+ days old. The verification is
30 seconds via a single grep.

### 8.5a Pre-commit hook + `--no-verify` escape hatch

Established 2026-05-25 alongside `tools/install-hooks.ps1` (Issue #29). After cloning the repo, run `./tools/install-hooks.ps1` to install the local pre-commit hook — it runs `qa/run_all.ps1 -Quick -SkipLua` and `tools/mod-lint/lint-mod.ps1` against staged `*.lua` / `*.cfg` / `*.ps1` / `*.mod` files before each commit, so cfg-drift, MOD_VERSION / title-suffix typos, duplicate hook registrations, and the other recurring bug classes catalogued in § 11a never reach CI. The installer is idempotent; the hook self-disables for commits that touch only docs / bundle binaries / other non-checked extensions.

**Gates block on ERRORS only.** A gate that finds an error fails the commit; WARNINGS print but do not block (this is the behavior a parallel `qa/run_all` change is landing). So the source commit + push that is part of every ship (§ 6.6) proceeds cleanly whenever the checks surface only advisory warnings; it does not get stuck behind a warning.

`git commit --no-verify` bypasses the hook for one commit. **Use it ONLY when a gate is itself wrong or out-of-scope for the change, and cite the reason in the commit message** so future-me can audit the override (`workshop-stage cfg rewrite already validated by VMBLauncher`, `lint false positive on <file>`, etc.). Prefer FIXING the gate over bypassing it. Never `--no-verify` to "fix on push" to dodge a real error; the GHA workflow runs the same checks and will block the merge anyway.

### 8.6 The "I'm about to add a defensive guard" gate
Before writing `if not X then return end` in a hook, answer in a comment:
1. What failure mode does this prevent?
2. What's the citation (CHANGELOG entry, crash GUID, vanilla source line)?
3. What does vanilla NORMALLY do here that this guard now skips?
4. Is skipping that mutation safe, or am I creating a new bug?

If you can't answer 1-4, DON'T add the guard.

---

## 9. Anti-patterns (observed in this repo's history — do not repeat)

### 9.1 Speculative defense stacking
**Symptom**: v0.9.8.3 → v0.9.8.4 → v0.9.8.5 → v0.9.8.6 → v0.9.8.7 in 24 hours,
each "fixing" a side effect of the prior. **Root cause**: not understanding
what vanilla does, just adding guards. **Fix**: revert all, understand,
ship one correct fix.

### 9.2 Wrong-key storage access
**Symptom**: `self._attachments[slot_name]` (always nil) instead of
`self._attachments.slots[slot_name]`. **Root cause**: writing guards from
memory instead of reading vanilla source. **Fix**: read vanilla source for
EVERY guard that touches non-obvious state.

### 9.3 Conditional registration with peer-sync
**Symptom**: a mod-load registration into `BuffTemplates`/`NetworkLookup`/
`DeusPowerUpsArray` gated by a per-user toggle → peers see different sequential
indices → `rpc_add_buff(integer_index)` crashes on join. **Fix**: pre-register
unconditionally in deterministic sorted order; gate only the offering pool.
See `DEVELOPMENT.md § Gated registration diverges across peers`.

### 9.4 Hot-reload assumption
Ctrl+Shift+R is **broken** for mods that hook unit creation
(`GearUtils.create_equipment`, `BackendUtils.get_item_units`) or use non-Lua
resources. Always full-restart VT2 after redeploying. See
`feedback_hot_reload_unfixable.md` memory.

### 9.5 1P animation overrides
**Symptom**: missing 3P attack on cross-character weapons (body holds previous weapon's idle stance — **NOT** a T-pose; see §9.8 terminology). **Wrong fix**: override `anim_event` or `wield_anim` (1P) per character. **Right fix**: only override 3P fields (`anim_event_3p`, `wield_anim_3p`). 1P is universal across characters; `first_person_base` is shared across all six characters and any weapon's 1P state machine plays correctly on every character's first-person view by default. See `weapon_tweaker/DEVELOPMENT.md` § "1P animations are universal — never touch" and `character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md` § "Three non-negotiable rules".

### 9.6 Adding fields to vanilla cfg fields you don't need
Especially `tags = [ ]` — causes ugc_tool first-upload to fail with 0x2.
Per `feedback_ugc_tool_forward_slashes.md`.

### 9.7 Skipping the bug-search-first protocol
Before "fixing" a crash, grep CHANGELOGs + memory for the literal crash
signature. Most surprising crashes are documented. Cost ~2 wasted ct versions
in 0.6.5-0.6.6 by skipping. See `feedback_search_changelog_for_known_crashes.md`.

### 9.8 Writing "T-pose" when the actual symptom is "missing event no-op"

VT2 characters do **NOT** T-pose when a `anim_event_3p` doesn't exist on the target weapon's 3P state machine. The actual behavior: the 3P body keeps the **last equipped weapon's idle stance** and silently no-ops the missing event. The attack animation simply doesn't play — no T-pose, no stuck frame, no engine fatal.

**Rule:** do NOT write "T-pose" in failure-mode descriptions, QA matrices, recipe docs, CHANGELOG entries, or commit messages. Use **"default stance of previous weapon"** or **"missing event no-op"** instead. T-pose specifically means the skeleton has no animation playing at all — rare; usually engine-fatal-adjacent — which is a different category of bug (typically a wholly broken state machine, or `Unit.animation_event` returning an error before any anim plays).

A missing `wield_anim_3p` is ALSO not a T-pose — it's the character not entering the new weapon's stance and instead staying in whatever the previous weapon's idle was.

**When auditing existing docs/code:** correct "T-pose" on contact. Most existing entries that say "T-pose" are technically wrong descriptions of "no-anim-played" symptoms. Established 2026-05-19 per user correction.

### 9.9a RPC payload without a schema gate

**Symptom**: host and client (or two peers) disagree on the positional shape
of a mod-defined `mod:network_send` payload, the receiver parses by position,
writes the wrong fields into local state, mod misbehaves with no log trace
pointing at the real cause. Likelihood scales with multi-build-per-day dev
iteration (host running latest dev, friend running stale Workshop bundle).

**Root cause**: implicit schema. The wire format is whatever the sender
happens to emit positionally; a receiver compiled against a different sender
shape has no way to know.

**Fix**: every mod that ships its own RPCs declares a `<MOD>_RPC_SCHEMA = N`
constant near `MOD_VERSION`. The constant is prepended as the FIRST positional
arg of every `mod:network_send`, validated as the first arg of every
`mod:network_register` callback, and on mismatch the receiver drops the
message with `_dbg_alert("[rpc:schema] <channel> mismatch ...")`. Graceful
degradation in both cross-version directions. Bump only when the payload
shape changes; one constant per mod across all the mod's RPCs.

Pilot: chaos_wastes_tweaker v0.7.114-dev (3 RPCs gated). Pattern + when-to-
bump + adding-new-RPCs + anti-patterns in `VMF_RECIPES.md § 10`. Follow-up
Issues propagate to cosmetics_tweaker, lobby_tweaker, enemy_tweaker,
crafting_in_modded, general_tweaker — track via GitHub Issues, not eager
churn.

### 9.9 Multi-return collapse via implicit `#t`

**Symptom**: a hook wrapper captures a wrapped call's tuple via
`local results = { f(...) }` and re-emits via `unpack(results)` or
`unpack(results, i)` without an explicit `j`. When the wrapped function
returns nils anywhere in its tuple (e.g. `GearUtils.spawn_inventory_unit`
returns `(weapon_3p, ammo_3p, weapon_1p, ammo_1p)` with `ammo_*` nil for
melee weapons), Lua 5.1's `#results` is **undefined** — it's a binary
boundary search over the array part, so the truncation point is
non-deterministic. Downstream consumers see randomly-nil unit handles.

**Root cause**: assuming `#table` is well-defined. It isn't, for arrays with
nil holes — see `CLAUDE.md` § "High-frequency engine quirks". The bug
silently propagates: the wrapper looks correct, the immediate caller sees
"sometimes" the right values, and a chained `mod:hook` consumer downstream
re-emits the corrupted tuple further.

**Fix**: When intercepting a function that may return nils anywhere in its
tuple, you MUST capture the count via `select("#", ...)` from the source
variadic, and pass `j` explicitly to `unpack`:

```lua
local function _capture(...) return select("#", ...), { ... } end
local n, results = _capture(xpcall(handler, _err_handler, func, ...))
return unpack(results, 2, n)   -- explicit j preserves nil holes
```

Pattern + extended example in `VMF_RECIPES.md § 2a`. Burned twice on the
same fix in 2 hours (weapon_tweaker v0.12.77 → .78 → .79 cycle on
2026-05-25). The new `mod:safe_hook` helper introduced in v0.12.77 was
itself an instance of the bug class warned about in the repo's own
`VMF_RECIPES.md § 2` — the helper failed to apply its own repo's recipe.

Cross-refs:
- `CLAUDE.md` § "High-frequency engine quirks" — short-form bullet on the
  underlying `#table` quirk.
- `VMF_RECIPES.md § 2a` — full recipe, burn history, canonical 4-return
  example.
- `weapon_tweaker/scripts/mods/weapon_tweaker/_safe_hook.lua` — the helper
  whose v0.12.79 fix carries the canonical pattern in code.

---

## 10. Mod maturity tiers (different bars for different mods)

### 10.1 Alpha (`-alpha`, `-dev`)
- Feature in flux. Breaking VMF changes tolerated.
- CHANGELOG required but can be terse.
- pcall on most hooks; some experimental hooks may be unprotected.
- Logging permissive.
- **Examples**: `modded_progression`, `lobby_tweaker`, `enemy_tweaker`.

### 10.2 Beta / Pre-stable
- Settings stabilizing. Breaking changes need migration code.
- CHANGELOG entries required for every release.
- pcall everywhere.
- Logging conservative.
- **Examples**: `chaos_wastes_tweaker`, `cosmetics_tweaker`,
  `character_weapon_variants`, `weapon_tweaker`.

### 10.3 Stable (no current mods at this tier yet)
- Breaking changes require deprecation + migration period.
- Every change requires CHANGELOG + verification (manual or automated).
- pcall everywhere + structured logging required.
- Test coverage expected (when we have it).
- Subagent pre-ship review required.

### 10.4 Frozen
- Mature mods we don't actively iterate on. Add `> FROZEN` banner at the top
  of the main lua.
- Candidates: `verminious_dreams_lighting` (per audit findings).
- Frozen mods still receive crash fixes but no new features.

---

## 11. Pending work tracking

**GitHub Issues are the source of truth for open work.** Per memory
`feedback_github_issues_for_pending_work.md` (binding rule 2026-05-23): items
that need doing belong in the issue tracker, not in markdown roadmaps that
silently rot. Issue list lives at
https://github.com/Ensrick/vermintide-2-tweaker/issues.

**Live status:**
```
gh issue list --repo Ensrick/vermintide-2-tweaker            # open
gh issue list --repo Ensrick/vermintide-2-tweaker --state all # incl. closed
```

### Process
1. When you find a pending item (audit, code review, deferred work),
   `gh issue create` it with appropriate labels.
2. Reference the issue number from the code (`-- See #N`) and any docs that
   describe the work.
3. When the fix ships, close the issue on GitHub with a comment linking to
   the commit / CHANGELOG entry.
4. Run `gh issue list` at the start of a session if you want a picture of
   what's open before diving in.

### Labels (canonical taxonomy — do NOT invent new status labels)

Every issue carries three dimensions: **status + type + mod**. Nothing else is a
status. This was ad-hoc "wild west" through 2026-07-03 (four overlapping status
labels, features untagged, `et`/`enemy` duplicated); the scheme below is the fix.

**Status (0–2) — the ONLY "ready to test" signal, applied when work has shipped:**
- `verify-fix` — a code fix shipped; the user tests it in-game.
- `diagnostics-armed` — a diagnostic/probe shipped; repro in-game to capture data.
- An issue with **neither** status label has **not been worked yet** (this is how the
  user sees the untouched backlog at a glance).
- **Retired 2026-07-03:** `verify-in-game` → merged into `verify-fix`; `probe-live` →
  merged into `diagnostics-armed`. Do not recreate them.

**Type (exactly 1):**
- `bug` — something is broken.
- `enhancement` — improve an existing feature, OR a chore / refactor / audit task.
- `feature` — a new capability or system that does not exist yet.
- `crash` is a **severity flag layered on `bug`** (a crash issue carries BOTH `bug`
  and `crash`), not a separate type.

**Mod (1+):** `ct`, `gt`, `gut`, `cim`, `wt`, `cwv`, `cosmetics`, `enemy`, `event`,
`mp`, `crt`, `cross-mod`, `tooling`. Each mod tag mirrors that mod's internal
`new_mod` id root (e.g. `cosmetics` = `cosmetics_tweaker`, `enemy` =
`enemy_tweaker`, `event` = `event_tweaker`). (`et` retired 2026-07-04 → split
into `enemy` + `event`: the single `et` label was ambiguous between the two
`*_tweaker` mods — its GitHub description said event_tweaker while a 2026-07-03
merge had repurposed it onto enemy_tweaker issues. Do NOT recreate `et`.)

**Optional modifiers (informational, never a substitute for a type):** `regression`
(a fix that broke a working feature), `audit`, `refactor`, `blocked`, `deferred`.

When you ship a fix or a diagnostic for an issue, add the matching status label in the
**same pass** as the CHANGELOG entry (rule #5 territory). Filing a new issue: give it a
type + mod immediately; add a status label only once you have actually shipped work.

**Dev localization tags move with the issue (issue #301).** Opening or closing an issue
that touches a dev-build feature means updating that feature's option-title status tag in
the SAME pass — e.g. add `[Issue N]` when you open, drop it (→ `[working]`/`[untested]`) when
you close, add `[verify-fix]`/`[diag]` when you ship a candidate fix or arm diagnostics. Full
tag vocabulary and rules: `LOCALIZATION_STANDARD.md` § 13 "Dev status tags"; the QA scan is
`qa/check_loc_tags.ps1`.

### What used to live here
A status roadmap (`✅ DONE / ⚠ PARTIAL / ❌ TODO` tables across "High ROI",
"Medium ROI", "Lower ROI", "Architectural", "Per-mod" subsections) was
maintained inline through 2026-05-23. It was removed because it duplicated
the GitHub issue list and silently drifted — exactly the failure mode §11
above is meant to prevent. The git history has the snapshots if you want to
see what was open on a given date.

## 11a. QA tooling — what's in place

| Tool | Location | Catches | Run via |
|---|---|---|---|
| `luacheck` | `.luacheckrc` + GHA | forward refs, unused vars, undefined globals, Lua 5.1 syntax | `luacheck . --no-config-default` |
| `check_cfg.ps1` | `qa/` | `tags=[]`, missing preview, wrong visibility, missing bug-report block, missing BMC | `.\qa\check_cfg.ps1` |
| `check_versions.ps1` | `qa/` | missing MOD_VERSION, cfg title-version drift, missing CHANGELOG entry | `.\qa\check_versions.ps1` |
| `check_localization.ps1` | `qa/` | unescaped `%`, referenced-but-undefined keys, missing `mod_description` | `.\qa\check_localization.ps1` |
| `check_file_sizes.ps1` | `qa/` | files over 1500-line target / 2500-line hard limit | `.\qa\check_file_sizes.ps1` |
| `check_stale_docs.ps1` | `qa/` | audit/review markdowns >14 days without SUPERSEDED banner | `.\qa\check_stale_docs.ps1 [-Fix]` |
| `run_all.ps1` | `qa/` | all of the above | `.\qa\run_all.ps1 [-Quick] [-SkipLua]` |
| GitHub Action | `.github/workflows/qa.yml` | runs all checks on push + PR | automatic |

Full check-to-bug-class map: [`qa/CHECKS.md`](qa/CHECKS.md).

---

## 12. Memory hygiene rules

### 12.1 What goes in memory (per the user's auto-memory system)
- **User preferences** that span sessions (workflow conventions, terminology).
- **Project-level invariants** (load-bearing rules, deprecation gotchas).
- **Recurring bug class signatures** (so future-me doesn't re-burn them).
- **External system pointers** (where bugs are tracked, what dashboards to
  check).

### 12.2 What does NOT go in memory
- Code patterns (read the code instead).
- Git history (use `git log`).
- Ephemeral task state (use tasks).
- Anything already in CLAUDE.md.

### 12.3 Periodic memory hygiene
- When MEMORY.md exceeds the soft limit (~24KB), prune. Move detailed memories
  into topic files; keep one-line index entries.
- When a memory's claim is wrong (stale code citation, code moved, fixed),
  update or delete. Don't leave wrong memories — they're worse than no memory.

---

## 12a. Mechanics knowledge substrate — capture doctrine

`docs/MECHANICS.md` is the repo's **provenance-enforced** index of how VT2 /
Stingray mechanics work. It exists to kill one specific failure: a session
drifts on how a mechanic works, **hallucinates to fill the gap**, and the wrong
claim propagates into code comments, docs, and crash triage. The substrate only
accretes GROUNDED inputs. `qa/check_mechanics_citations.ps1` fails on any
untagged factual bullet (wired into `run_all.ps1`, advisory).

Every factual bullet carries one provenance tag: `[src: file:line]` (decompiled
source, opened and verified — the gold standard), `[dump: file]` (in-game
runtime dump), `[memory: note]` (a memory note that itself cites ground truth),
`[bugclass: §N]` (carried from `docs/BUG_CLASSES.md`), `[user: YYYY-MM-DD]`
(maintainer stated it — lowest tier, flag for source-confirmation), or
`[unverified]` (an explicit, COUNTED honest gap). Full schema at the top of
`docs/MECHANICS.md`.

### The four capture rules (this is the loop that keeps it growing from real inputs)

1. **Before stating ANY mechanic** — in a code comment, a doc, or a reply to the
   user — grep the decompiled source FIRST and cite `file:line`, OR write
   `[unverified]` / say "I don't know." NEVER confabulate. (This generalizes the
   `feedback_vmf_ui_no_guessing` "read the source before proposing" rule from VMF
   UI to ALL mechanics. The §13 "Don't invent internals" rule in the global
   prefs is the same principle.)
2. **When the decompiled source confirms a fact during work** → append a
   MECHANICS entry with `[src: file:line]`, in the SAME response as the code
   edit. Capture-as-you-verify; don't batch it for later (it rots).
3. **When the maintainer states a mechanic** → capture it to MECHANICS with
   `[user: <date>]`, and where possible add a source cross-check. Promote the tag
   `[user]` → `[src]` once the decompiled source confirms it. This is the
   "information the maintainer gives is added there" loop — it is explicit and
   cheap on purpose.
4. **When an in-game dump is collected** (the gt name-dump, ANIMATION_RESEARCH
   probes, a `/dump_*` capture) → reference it `[dump: <file>]`.

### Invariants

- The substrate is APPEND-mostly. Entries get PROMOTED up the provenance tiers as
  they're confirmed; they are never silently invented or downgraded.
- `[unverified]` is the CORRECT state where no grounded source exists. It is an
  honest, surfaced gap — NOT a license to fill it from model knowledge. The lint
  counts these as the known-gaps backlog so they stay visible.
- MECHANICS POINTS at memory / source / BUG_CLASSES; it does not restate them.
  Don't create a fourth knowledge surface that duplicates prose.

---

## 13. When this doc is wrong

This doc is itself versioned. When you encounter a rule that conflicts with
reality, or a workflow that's been proven counter-productive, propose an
update to this doc in the same PR as the work. Don't silently ignore the rule.

The rules are recommendations from observed pain. New pain may justify new
rules; old pain that's been solved may justify deleting rules. Both are fine.

---

## 14. Quick reference card

```
BEFORE coding a fix:
  - Read crash log / repro evidence
  - Read current source (not stale audit line numbers)
  - Read vanilla source if hooks involved
  - State: failure mode, citation, why this fix is the right shape

WHEN coding:
  - File ≤1500 lines target, ≤2500 hard
  - Logs prefixed [mod:feature]
  - mod:info / mod:warning / mod:error / mod:echo (correct level)
  - pcall wrap hooks that mutate non-trivial state
  - Comment: why, not what; cite when fixing a bug

BEFORE shipping:
  - MOD_VERSION bumped
  - CHANGELOG entry written
  - No forward-ref bugs (visually verify; future: luacheck)
  - No new "guard ≠ bail" violations
  - Subagent pre-ship review for hot mods
  - Approval axis checked: -dev/-alpha/-beta = ship with NO ask; clean version = fresh per-build signal (sec. 6.6)

AFTER shipping:
  - workshop_log.txt shows "Uploaded new content" for the item
  - git add / commit / push the source (the commit is part of the ship, sec. 6.6)

WHEN BLOCKED:
  - Memory + CHANGELOG grep for the literal symptom
  - Dispatch Explore subagent if it needs >3 files
  - Don't add speculative defenses
```

---

## 14a. Persistence-after-fix protocol (assume I misfixed first)

Established 2026-05-25 EOD after I shipped gt v0.2.61 → .62 → .63 → .64 → .65 in ~45 minutes, each time claiming the bug was fixed, each time the user restarted and hit a NEW bug or the SAME bug pattern from a missed call site. User-facing impact: indistinguishable from gaslighting — "I fixed it, restart" → still broken → "oh that's a new bug, restart again" → etc.

### The binding rule

When a user reports that a bug PERSISTS after I claimed "shipped / fixed":

1. **First hypothesis: I didn't actually fix it.** Not "you have stale code." Not "your session predates the deploy." Not "Steam hasn't propagated."
2. **Verify the three layers before considering environmental causes:**
   - **Source:** read the source file. Does the fix actually exist in the code right now? (E.g. did the Edit fail silently? Was the file modified after my edit by another agent?)
   - **Bundle:** `Get-ChildItem <mod>/bundleV2/` — is the .mod_bundle newer than the source file? If source is newer than bundle, the bundle is stale.
   - **Loaded mod:** in the user's latest log, find the `<<crashify-property>>Mod:<id>:<name> v<version>` line. Does the loaded MOD_VERSION match the version I claimed shipped?
3. **Only after all three verify clean** may I suggest restart / Steam propagation / friend re-pull as the next hypothesis.

### Also: search for the SAME bug pattern across the whole file / module before declaring done

When fixing one instance of a class (e.g. `event:register(mod, "ev", FN_VALUE)` — Stingray expects string), grep the whole repo for the pattern BEFORE marking the task done. The user shouldn't have to restart 3 times to find 3 instances of the same bug. One grep finds all of them.

### Why this rule exists

The lt-merge session above shipped 5 bumps in 45 minutes:
- v0.2.61 — claimed fix for widget#103; was correct but I missed event_register bug entirely
- v0.2.62 — added /gt_lobby_motd_set chat command (a new feature, not a fix)
- v0.2.63 — claimed fix for event_register; fixed 2 of 3 sites (I missed session_ignore)
- v0.2.64 — fixed the 3rd site; introduced no new fix beyond that
- v0.2.65 — claimed fix for `set_lobby_data` nil spam; needed defensive type-check guard

Each "fix" surfaced another latent bug because I patched whack-a-mole without auditing the broader migrated code holistically. User had to restart 5 times to reach a clean state. From their seat, each restart cycle was "fixed → not fixed → fixed → not fixed."

### Detection mechanism

When the user says "still broken" / "errors persist" / "you didn't fix it":
- Apply this protocol BEFORE responding.
- Verify the three layers programmatically (don't trust the agent report; read the actual file).
- If all three verify clean and bug genuinely persists → THEN suggest restart.
- If any of the three doesn't verify → that's the real root cause, fix it.

Burn history: 2026-05-25 EOD (this very session).

## 15. Every bug requires a test

Established 2026-05-23 after the DORMANT_BOON_RARITY scope-bug shipped twice (crash GUIDs 4c5d2157 + prior chest-of-trials crash).

### The rule

When fixing any user-reported bug or any internal-discovered defect, the fix is incomplete until:

1. A regression test exists that would FAIL if the bug returned.
2. The test runs as part of the mod's `/<prefix>_regression_test` chat command.
3. The test is documented in the mod's CHANGELOG.md entry for that fix version, with the exact identifier so it's findable later.

No exceptions for "tiny" bugs. The bigger the bug seems, the more obvious the test should be — and yet, today's scope bug shipped without one even though the recon agent identified the cause.

### Test categories per mod

- **Source-pattern check**: embed a sentinel literal in the source body (e.g. `STARTING_COINS_MODE_MARKER = "setter-override-via-setup_run-arg"`); the regression check at boot asserts the literal is present in the compiled bundle. Catches accidental code deletion / refactor regression.
- **Runtime-state check**: in-keep assertion that touches the actual runtime structure (e.g. `_rt_register("dormant_boon_rarity_is_table", function() if type(_G.DORMANT_BOON_RARITY) ~= "table" then return "..." end end)`).
- **Disable-mode check**: when a feature is disabled, verify the disable is real — not just "the toggle says off" but "the feature's table is empty, the feature's setting key is not consumed, the feature's chat command is absent."

### When the test feels redundant

If the test feels redundant with the lint, write it anyway. Lints catch new code; tests catch live runtime behavior. They cover different surfaces. Memory `reference_redundant_safeguards_ok` already endorses this. **Belt-and-suspenders is the rule, not the exception: a lint-covered fix is PARTIAL until it ALSO has a runtime `_rt_register` check — both the static-pattern lint and the live-state assertion are required for PASS.** (Codified 2026-05-24 after the §15 test-coverage audit promoted five lint-only fixes to lint+runtime.)

### Defensive wrapper patterns

Per the chest-of-trials root-cause analysis (`DORMANT_BOON_RARITY` indexed by closures that resolved the name to `_G.DORMANT_BOON_RARITY` (nil)):

1. **Top-level data tables consumed by mid-file closures**: declare at the TOP of the file (above all closures), not late. If declared late, promote to `_G.<NAME>` at top so all closures resolve consistently.

2. **Global table indexes** that could be nil during early boot: wrap in `(rawget(_G, "<NAME>") or {})` sentinel before subscript.

3. **NetworkLookup / BuffTemplates / DeusPowerUpTemplates**: always `rawget(table, key)` — these install strict `__index` metatables that crashify on missing key. Memory `reference_vt2_strict_lookup_rawget`.

4. **Every disabled feature**: ship with a regression check that ASSERTS THE DISABLE (e.g. `<feature>_NOT_registered`, `<feature>_NOT_in_pool`). Re-enabling the feature would fail those checks until they're rewritten — guards against half-revert.

---

*Last updated: 2026-07-01 — sec. 6.5/6.6 ship doctrine rewritten (dev builds
pre-authorized for the full pipeline + git commit/push; stable promotions need a
fresh per-build signal), sec. 8.5a gate semantics (errors block, warnings
report), sec. 14 card gained the approval axis + AFTER-shipping steps.
Prior update 2026-05-23 — §7 documentation standards expanded: canonical doc
map (repo-root + per-mod tables with update triggers), three-bucket model for
non-canonical docs (Reference / POSTMORTEMS.md / `_investigating/`), audit
snapshot policy (gitignored, distill on action), supersession banner preserved,
doc creation gate, filename conventions. §1 baseline refreshed (QA tooling now
in place); §11 roadmap moved to GitHub Issues per §11's own discipline.
Initial draft: 2026-05-22.*
