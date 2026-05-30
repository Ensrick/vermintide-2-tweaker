# VMF Recipes & Gotchas

Cross-cutting Vermintide Mod Framework rules that bite every mod in this repo
at least once. Each entry: the rule, why it bites, how to apply, and the burn
history that justified writing it down.

Surface-level callouts from this file are referenced in `CLAUDE.md` § Hooking.
The full mechanics live here.

---

## 1. `mod:hook_safe` does NOT chain on the same Class.method

**Rule:** Never register two `mod:hook_safe(Class, method, ...)` calls for the
same `Class + method` pair in a single mod. VMF treats the second registration
as a **replacement**, not a chain. Only one of the two callbacks runs at
runtime, with **no error, no warning, no log** — just silent shadowing.

### Why

VMF's hook registry keys by `(Class, method)` and overwrites. The diagnostic
trace shows `Hooking '<method>' from [<Class>]` printed **twice** (with the
**identical** Origin function pointer), but at runtime neither body executes
on the shadowed path.

This also extends to `mod:hook` (chainable wrappers) in some cases — VMF's
internal chain dispatch can drop registrations on the same `(Class, method)`
pair if registered from the same mod within the same module load. Treat both
the same: **one handler per `Class + method` per mod**.

### How to apply

Before adding `mod:hook_safe(Class, method, ...)`:
1. Grep the mod for existing `mod:hook_safe.+method` on the same class.
2. If one exists, **consolidate both concerns into a single callback**.
   `hook_safe` runs after the original — ordering inside the body is your
   choice.
3. If a hook "should fire" per the install log but its body never runs,
   check for duplicates as the first diagnosis before chasing class derivation,
   RPC routing, or the husk-pair issue.

### Burned

cwv v0.1.96 → v0.1.99 (2026-05-07). Two `mod:hook_safe("PlayerProjectileUnitExtension", "init", ...)` registrations (a diagnostic trace + the runtime fix) silently no-opped. Wasted three versions debugging "the hook isn't firing" before the duplicate was spotted.

---

## 2. Hook wrappers collapse multi-return to one value

**Rule:** When wrapping a hooked function's return through another function,
multi-returns silently collapse to **one**. Writing
`return wrapper(func(self, ...))` drops every return after the first into the
wrapper's argument list, where they are then dropped on the way out.

### Why

Lua's call-position rule for multi-returns: the trailing function call expands
to all returns only if it is the **last** expression in the outermost
parenthesised list. As a nested call, only the first return passes through.

### Burned

enemy_tweaker v0.2.4: `HordeSpawner.compose_blob_horde_spawn_list` returns
`(spawn_list, num_to_spawn)`. Hook was
`return _apply_breed_swap(func(self, composition, ...))`. `_apply_breed_swap`
declared one parameter, so `num_to_spawn` reached the caller as `nil` and the
next `for i = 1, num_to_spawn do` blew up with
`horde_spawner.lua:1060: 'for' limit must be a number`. Same shape of failure
as `hook_safe` not chaining — a quiet wrapping bug that only manifests at the
call site, not the hook.

### How to apply

Whenever the wrapped function has more than one return value (VT2 spawn /
composition / get_loadout / get_item_units functions love returning 2-3
values), expand:

```lua
-- WRONG -- num_to_spawn collapses to nil at the caller
mod:hook("HordeSpawner", "compose_blob_horde_spawn_list", function(func, self, comp, ...)
    return _apply_breed_swap(func(self, comp, ...))
end)

-- RIGHT -- capture every return, transform the one you need
mod:hook("HordeSpawner", "compose_blob_horde_spawn_list", function(func, self, comp, ...)
    local spawn_list, num_to_spawn = func(self, comp, ...)
    return _apply_breed_swap(spawn_list), num_to_spawn
end)
```

When in doubt, grep the source file's `return ...` line for the function
before writing the hook.

---

## 2a. Variadic capture also needs nil-hole-safe unpack

**Rule:** When intercepting a function's return tuple via variadic capture
(`local results = { f(...) }`), you MUST pass an explicit `j` argument to
`unpack(results, i, j)` derived from `select("#", ...)`. **Never** rely on
bare `unpack(results)` or `unpack(results, i)`. In Lua 5.1, `#table` is
undefined for arrays with nil holes — the length operator does a **binary
boundary search** over the array part and may land at any border, so
`{1, nil, 2, nil, 3}` can report length `1`, `3`, or `5` depending on
implementation internals and table history.

### The bug

```lua
-- WRONG -- nil holes truncate the return tuple non-deterministically
mod:hook("SomeClass", "some_method", function(func, self, ...)
    local results = { xpcall(handler, _err_handler, func, self, ...) }
    if results[1] then
        return unpack(results, 2)   -- defaults to j = #results, undefined with nils
    end
end)
```

When `handler` (and therefore the wrapped `func`) returns a tuple with nils
anywhere — e.g. `(weapon_3p, nil, weapon_1p, nil)` — `#results` becomes
`{true, weapon_3p, nil, weapon_1p, nil}` whose `#` may resolve to `1`, `2`,
`4`, or `5`. Truncation is silent: downstream consumers that read positions
3 / 5 see `nil` where the source actually returned a unit handle, and any
chained `mod:hook` consumer that re-emits the tuple propagates the corrupted
shape further.

### The fix

```lua
-- RIGHT -- capture the real arity from the source variadic
local function _capture(...) return select("#", ...), { ... } end
local n, results = _capture(xpcall(handler, _err_handler, func, ...))
if results[1] then
    return unpack(results, 2, n)   -- explicit j preserves nil holes
end
```

`select("#", ...)` reads the **actual** number of values in the variadic
(including trailing nils) at the point it's called, before the values land
in a table where nils become indistinguishable from "no entry". Pass that
count as `j` to `unpack` so the nil holes round-trip cleanly.

### Canonical 4-return example with nil holes

`Vermintide-2-Source-Code/scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua:273`
`GearUtils.spawn_inventory_unit` returns
`(weapon_unit_3p, ammo_unit_3p, weapon_unit_1p, ammo_unit_1p)`. For melee
weapons the two `ammo_*` slots are **nil** — positions 2 and 4 are nil
holes, position 1 and 3 are real unit handles. Any `mod:hook` wrapper that
captures the return tuple via `{ ... }` and re-emits it via bare `unpack`
will randomly drop position 3 (the 1P weapon unit), the 1P weapon hand goes
unrendered, and downstream readers (CWV, cosmetics_tweaker glow apply, etc.)
chain off the corrupted shape.

### Burned

weapon_tweaker v0.12.77 → v0.12.78 → v0.12.79 fix cycle on 2026-05-25.

- **v0.12.77** (Issue #26): introduced `mod:safe_hook` whose handler-result
  capture collapsed every return after position 1 into a single value.
- **v0.12.78**: replaced the collapse with `unpack(results, 2)` — still
  broken because `#results` is non-deterministic with nil holes from
  `GearUtils.spawn_inventory_unit`'s melee-weapon return.
- **v0.12.79**: `select("#", ...)` + `unpack(results, 2, n)` — finally
  correct.

Proximate symptom: `tostring(math.huge) == "inf"` on the ammo HUD plus
corrupted 1P weapon rendering, both downstream of `spawn_inventory_unit`'s
position-3 (`weapon_unit_1p`) being randomly truncated to nil. The bug class
is exactly what § 2 above warns about, applied to the variadic-capture
shape — the new `safe_hook` helper failed to apply its own repo's recipe
twice in two hours.

### Cross-refs

- `CLAUDE.md` § "High-frequency engine quirks" — short-form bullet on the
  same `#table` quirk.
- `PROJECT_STANDARDS.md` § 9 — anti-pattern listing for "multi-return
  collapse via implicit `#t`".
- `weapon_tweaker/scripts/mods/weapon_tweaker/_safe_hook.lua` — the helper
  whose v0.12.79 fix carries the canonical pattern in code.

---

## 2b. Pcall-isolated hooks (`mod:safe_hook`) — drop-in `mod:hook` wrapper

**Rule:** Default to `mod:safe_hook` / `mod:safe_hook_safe` (where available)
for any hook body that is not load-bearing for compile-time hook validation.
A consumer's raise should kill that consumer's behavior **only** — never
silently take out unrelated downstream mod hooks on the same `(Class,
method)`.

Tracked under Issue #26. First-class implementation lives at
`weapon_tweaker/scripts/mods/weapon_tweaker/_safe_hook.lua` and attaches
`mod.safe_hook(self, class, method, fn)` + `mod.safe_hook_safe(self, class,
method, fn)` methods. Same signature as `mod:hook` / `mod:hook_safe`; wraps
`fn` in xpcall.

### Why

VMF's chain dispatch (`vmf/modules/core/hooks.lua` → `get_hook_chain` +
`create_specialized_hook`) walks the registered `mod:hook` bodies WITHOUT
pcall. A raise inside consumer A's `mod:hook` body propagates up the chain,
kills every later consumer's registration on the same target silently (no
log, no error, no Crashify entry), and may pollute the engine call stack
mid-frame. In-the-wild symptom: cosmetics_tweaker hook A raises -> wt hook
B never fires -> user sees a missing feature with no diagnostic line to
grep for.

`hook_safe` (`HOOK_TYPE_SAFE`) is run under VMF's `safe_call_nr` xpcall
internally, so the chain-walking side of that path is already protected.
`safe_hook_safe` still adds value by attributing the error log to the
specific mod's prefix (`[wt:safe_hook_safe] Class.method raised: ...`)
instead of VMF's generic `(safe_hook)` tag.

### How to apply

```lua
-- BEFORE — bare mod:hook, raise kills every later consumer in the chain
mod:hook("SimpleInventoryExtension", "wield", function(func, self, slot_name, ...)
    _populate_unit_state_from_wield(self, slot_name)
    return func(self, slot_name, ...)
end)

-- AFTER — safe_hook, raise logs + falls through to vanilla, chain intact
mod:safe_hook("SimpleInventoryExtension", "wield", function(func, self, slot_name, ...)
    _populate_unit_state_from_wield(self, slot_name)
    return func(self, slot_name, ...)
end)
```

On error, the helper logs `[wt:safe_hook] <Class>.<method> raised: <err>` +
`Script.callstack()` via `mod:error`, then calls `func(...)` so the engine
path and every later mod's hook on the same target keep running.

### When to use vs raw `mod:hook`

- **Default to `safe_hook`** for any consumer body that doesn't need a
  raise to propagate (i.e. ~99% of mod hooks).
- **Use raw `mod:hook`** only when you genuinely WANT a raise to surface
  immediately at the call site — e.g. compile-time hook validation,
  test-mode assertions, or a defensive `error(...)` you placed inside a
  hook body that you want to crash the game on.
- **Use raw `mod:hook_safe`** when a single per-mod log prefix tag isn't
  worth the wrapper indirection cost (VMF already pcalls the body
  internally — `safe_hook_safe` just adds the `[<mod>:...]` prefix).

### Scope

v1 is self-contained per mod — each mod that wants the helper drops its
own `_safe_hook.lua` and requires it after `MOD_VERSION`. Cross-mod sharing
(helper in `bt` or a `vmf_shared/` package) is a Wave-2 concern; v1
intentionally avoids the load-order coupling.

### Burned

Issue #26: cosmetics_tweaker raised inside a hook body on `SimpleInventory
Extension.wield`; wt's wield hook (same Class.method, later in the chain)
silently no-opped. User-visible symptom was "cross-character animation
redirect dropped out after entering keep" with zero log lines to trace.
Resolved in `weapon_tweaker` v0.12.77-dev — 5 representative hook sites
converted to demonstrate adoption. Wider rollout follows as future
patches.

### Implementation reference

- `weapon_tweaker/scripts/mods/weapon_tweaker/_safe_hook.lua` — the helper.
- `weapon_tweaker.lua` — converted sites at `SimpleInventoryExtension.wield`,
  `SimpleHuskInventoryExtension.wield`, `GearUtils.create_equipment`,
  `GearUtils.spawn_inventory_unit`, `LevelEndView._verify_weapon_data`.
- `/wt_regression_test wt_safe_hook_installed` — sanity-checks marker
  constant + `mod.safe_hook` callable.

### Layer 3: traced_hook — safe_hook plus structured entry/exit logging

`mod:traced_hook(class, method, handler)` and `mod:traced_hook_safe(class,
method, handler)` are Layer-3 wrappers that delegate to `safe_hook` /
`safe_hook_safe` (Layer 2) AND emit structured entry/exit log lines gated
on `mod:get("enable_debug_logging")`. Shipped in `weapon_tweaker` v0.12.84-dev.

Log format:

```
[wt:trace] event=enter class=<C> method=<m> n_args=N
[wt:trace] event=exit  class=<C> method=<m> n_returned=M
```

When the toggle is OFF, no trace lines emit and the wrapper is
semantically identical to `safe_hook`. When ON, every fire emits paired
entry/exit lines — directly catches "did the hook fire?" and "did it
return what we expected?" diagnostics. The v0.12.77/.78/.79 safe_hook
multi-return bug cycle would have surfaced in one run with trace on.

```lua
-- Layer 1: bare mod:hook — no isolation, no observability.
mod:hook("GearUtils", "spawn_inventory_unit", function(func, ...) ... end)

-- Layer 2: safe_hook — pcall-isolated + multi-return-safe.
mod:safe_hook("GearUtils", "spawn_inventory_unit", function(func, ...) ... end)

-- Layer 3: traced_hook — Layer 2 PLUS [wt:trace] entry/exit log lines.
mod:traced_hook("GearUtils", "spawn_inventory_unit", function(func, ...) ... end)
```

**RATE-LIMIT CAVEAT.** Do NOT wrap per-frame hooks (`mod.update`, frame-
rate state hooks, etc.) in `traced_hook` — they fire 60+ times/sec and
would flood the log when the toggle is on. Per-frame hooks stay on
`safe_hook` with an inline comment noting the rate-limit reason.

Layer 3 does NOT re-implement pcall isolation or multi-return preservation
— delegates to safe_hook so there's ONE canonical `select("#", ...)` +
`unpack(..., j)` site (Layer 2's `_capture` closure). Future fixes to
the multi-return path automatically propagate.

### When to use traced_hook vs safe_hook

- **traced_hook** — when fire-confirmation + return-shape visibility is
  load-bearing for diagnosing a class of bug (chain consumer collapse,
  multi-return truncation, cross-mod hook conflict). Event-rate hooks
  only — wield, equip, mission-spawn, keep-load.
- **safe_hook** — default. When chain isolation is the only requirement.
  Per-frame hooks ALWAYS stay here (never traced_hook).

### Layer 3 implementation reference

- `weapon_tweaker/scripts/mods/weapon_tweaker/_safe_hook.lua` — Layer 3
  block at the bottom of the file.
- `weapon_tweaker.lua` — three migrated sites (`SimpleInventoryExtension.wield`,
  `GearUtils.create_equipment`, `GearUtils.spawn_inventory_unit`). Other
  safe_hook sites remain on Layer 2.
- `/wt_regression_test wt_traced_hook_present` — sanity-checks Layer 3
  marker constant + `mod.traced_hook` callable + smoke-tests return-shape
  preservation through the wrapper with toggle off and on.

---

## 3. `mod:network_send` recipients — `"server"` is silently dropped

**Rule:** VMF's `mod:network_send(rpc_name, recipient, ...)` accepts exactly
**four** recipient forms:

| Recipient | Meaning |
|---|---|
| `"all"` | every peer including self |
| `"others"` | every peer except self |
| `"local"` | self only |
| `<peer_id_string>` | specific peer (literal Steam peer id) |

Anything else — including `"server"`, `"host"`, `"clients"`, `"server_peer"` —
falls through `convert_names_to_numbers` (`vmf/scripts/mods/vmf/modules/core/network.lua`) and is treated as a literal peer_id.
The downstream `_vmf_users[peer_id]` lookup fails, `send_rpc_vmf_data` returns
silently — **no error, no warning, no wire activity**.

### How to apply

To send to the host from a client, fetch the host's real peer_id:

```lua
-- Canonical engine API (see vanilla imgui_career_debug.lua:153,
-- versus_mechanism.lua:1845). Returns nil during host migration /
-- session-join / level transition — always guard.
local host
if Managers.mechanism and Managers.mechanism.server_peer_id then
    host = Managers.mechanism:server_peer_id()
end
-- Fallback for the brief window where mechanism hasn't published yet but
-- GameNetworkManager already wired its subcomponents.
if not host then
    local nm = Managers.state and Managers.state.network
    host = nm and ((nm.network_client and nm.network_client.server_peer_id)
        or (nm.network_server and nm.network_server.server_peer_id))
end
if not host then
    -- Defer or pending-queue the send.
    return
end
mod:network_send("my_rpc_request", host, payload)
```

**Do NOT use `Managers.state.network.server_peer_id`.** That path always
reads nil — `Managers.state.network` is the `GameNetworkManager` (set in
`state_ingame.lua:2194`) which has no such field directly. The
`server_peer_id` lives one level deeper on `.network_client` (client) or
`.network_server` (host). Burned in general_tweaker v0.2.49-dev: every
client toggle refused with "host peer_id not yet known". Fixed v0.2.50-dev.

### How to detect in YOUR mod

- Add `mod:info("[my_rpc emit] CLIENT->req ...")` right before any
  `mod:network_send` you THINK targets the host.
- On the host, register receiver with `mod:info("[my_rpc recv] ...")` at the
  top of the handler.
- Test in a real lobby with the local user as CLIENT (not host). If emit
  fires but recv never does, `"server"` is the most likely culprit.

### Why this is hard to catch

- **Solo testing:** only one peer, `network_send` short-circuits to local.
- **Host-as-tester:** every `_is_local_server() then "all" else "server"`
  branch hits the "all" path. The broken `"server"` line never fires.
- The VMF API docs at vmf-docs.verminti.de don't enumerate the valid
  recipients — most modders guess `"server"` because it reads naturally.

### Burned

cosmetics_tweaker v0.8.67-dev → v0.9.0.15-hotfix (2026-05-19/20). All prior
testing had PC-A as host. When PC-A finally connected as CLIENT, the silent
drop killed the entire LA cosmetic sync chain. ~8 hours of debugging, two
parallel research agents, before root cause was identified.

general_tweaker v0.2.48-dev (2026-05-24). Same `"server"` mistake in the AI
Takeover client-toggle path. Fixed in v0.2.49-dev; uncovered the related
recipient-state bug below (gotcha 3a).

---

## 3a. VMF `_vmf_users` can be silently dropped by host bot churn

**Rule:** Even with a valid `peer_id` recipient (per gotcha 3 above),
`mod:network_send` silently no-ops when the recipient peer is missing from
VMF's internal `_vmf_users` table. VMF's `convert_names_to_numbers`
returns nil; `send_rpc_vmf_data` returns without sending. The bug that
removes the host from a client's `_vmf_users` is:

```lua
-- vmf/scripts/mods/vmf/modules/core/network.lua:375-404 (upstream)
vmf:hook(PlayerManager, "remove_player", function (func, self, peer_id, ...)
  -- ...
  if _vmf_users[peer_id] then
    for _, player in pairs(Managers.player:human_players()) do
      if player.peer_id == peer_id then
        -- removes peer_id from _vmf_users
        break
      end
    end
  end
end)
```

When the host's own bot is removed (`remove_player(host_peer, bot_local_id)`
fires on every client), the "still has human_player on this peer_id" loop
matches the HOST's own human player, so VMF removes the whole host peer
from the client's `_vmf_users`. Host bot churn at mission load (slot
reassignment, profile reset, etc.) is the common trigger.

Once dropped, VMF never auto-re-adds the host until something causes a
re-handshake — and `add_remote_player` only sends a ping when the new
player is `player_controlled`, which fires sporadically.

### How to apply

Before any client → host `mod:network_send`, force a VMF re-handshake:

```lua
local vmf = get_mod("VMF")
if vmf and vmf.ping_vmf_users then
  pcall(vmf.ping_vmf_users)  -- pcall in case future VMF changes the API shape
end
-- DO NOT send inline — the pong round-trip is async (~50-300 ms Steam P2P).
-- Queue the send for ~0.4 s later and retry 2-3 times in case the
-- handshake hasn't landed yet. Mod-update tick is the right place.
```

The receiver must be idempotent (no-op when state already matches) so
duplicate sends from retries are safe.

### How to detect in YOUR mod

Grep both client + host logs for `Added.*VMF users` and `Removed.*VMF users`
around the time of any failed RPC. If client log shows an `Added` followed
shortly by a `Removed` for the host peer with no subsequent `Added`, this
is the bug.

### Burned

general_tweaker v0.2.49-dev → v0.2.52-dev (2026-05-24). v0.2.49 fixed
gotcha 3 (`"server"` recipient). v0.2.50 fixed wrong server_peer_id path.
v0.2.52 added re-handshake + queued send because the RPC was STILL silently
dropping at the recipient layer. Log diff between PC-A host and PC-B client
showed the host's `Added → Removed` 2 ms apart at mission load, with no
re-Add for the next 47 seconds before the user's toggle attempt at
23:10:58.

---

## 4. RPC string parameter cap = 500 chars (and VMF JSON-packs all args)

**Rule:** Stingray hardcaps every RPC string parameter at **500 characters**
(`scripts/helpers/network_utils.lua:93`, `STRING_MAX = 500`). VMF's
`mod:network_send` JSON-encodes every user arg into a single string parameter,
so any payload that exceeds the cap silently no-ops.

### Why

`ModManager.network_send(destination_peer_id, port, payload)`
(`mod_manager.lua:595`) calls
`RPC.rpc_mod_user_data(channel_id, src, dst, port, payload)`. VMF wraps
`mod:network_send(rpc_name, target, ...args)` by JSON-encoding
`(rpc_name_id, args...)` into the single `payload` string. A 105-key settings
table → ~4-5KB JSON → fatal:

```
scripts/managers/mod/mod_manager.lua:627: Failed to pack parameter 3,
too many characters in string with max length 500
```

The error fires inside VMF's safe-hook wrapper so it **never surfaces as a
crash** — the broadcast silently no-ops and clients receive nothing.

The cap is **hardcoded in the engine** and not affected by any in-game
setting. `max_upload_speed = 512` is bandwidth throttling, unrelated — the
500/512 proximity is a red herring. `small_network_packets` controls MTU
(576), also unrelated.

### Fix: mirror vanilla `shared_state.lua` chunking

`scripts/network/shared_state.lua:288-330` is the canonical pattern: split the
payload into 500-char chunks, send each with a `complete` flag, reassemble on
the receiver. For VMF mods, **budget chunks at ≤400 chars** to leave headroom
for VMF's `[mod_id, rpc_id]` envelope plus the JSON wrapper
`[session, seq, total, "<chunk>"]` (~20 chars).

Canonical implementation: ct v0.7.59-alpha, `chaos_wastes_tweaker.lua:252-389`.
Encodes payload via `cjson.encode`, splits at `SYNC_CHUNK_SIZE = 400`, sends
`(session, seq, total, chunk_str)` per chunk. Receiver buffers per-sender
keyed on `session`; a different session id resets the buffer. Decodes only
when `received == total`.

`cjson` is a global in VT2 — no `require` needed.
`Application.time_since_launch()` gives a monotonically-increasing float
suitable for generating session ids.

### How to spot

- A `mod:network_send` payload that includes a table over ~10 keys, or any
  string field over ~100 chars.
- Symptom is **silence**, not a crash — host-only logs may show the pack
  error if VMF's safe-hook isn't swallowing them; clients show nothing.

### Burned

ct v0.7.55 → v0.7.58 silently broken (3 versions). When settings sync silently
dies, client-side buff registration diverges from host → downstream
`rpc_add_buff` crashes on unknown `buff_template` indexes (see Stingray gotcha
"Gated registration diverges across peers" in `DEVELOPMENT.md`).

---

## 5. VMF dropdown options tables are MUTATED in place — never share

**Rule:** VMF's `localize_dropdown_data`
(`vmf/scripts/mods/vmf/modules/core/options.lua`) does:

```lua
for _, option in ipairs(options) do
    option.text = mod:localize(option.text)
end
```

That mutates the **same option table the modder passed in**. If two dropdowns
share one `options` table reference, the first dropdown converts
`option.text` from `"my_opt_off"` → `"Match (vanilla)"`. The next dropdown
then calls `mod:localize("Match (vanilla)")` — which has no loc entry — and
gets `<Match (vanilla)>`. Each additional sharing dropdown wraps another `<>`
pair, producing `<<<...>>>` cascades.

### The fix

**Each dropdown widget must get its OWN options table.** Either inline them
per-dropdown, or use a factory function that returns a freshly-built table:

```lua
-- WRONG: shared reference
local _MIMIC_OPTIONS = { { text = "mimic_opt_off", value = "off" }, ... }
{ ..., options = _MIMIC_OPTIONS },  -- dropdown 1
{ ..., options = _MIMIC_OPTIONS },  -- dropdown 2 -> brackets

-- RIGHT: factory per dropdown
local function _mimic_options()
    return { { text = "mimic_opt_off", value = "off" }, ... }
end
{ ..., options = _mimic_options() },  -- fresh table
{ ..., options = _mimic_options() },  -- another fresh table
```

A `_build_*`-style function is fine — but **don't cache the result at file
scope** and assign that single cached value to multiple dropdowns. Inline
literals like `options = { { text = "preset_off", value = "off" }, ... }`
also create a new table per widget.

### Diagnostic signature

Single `<key>` is a true missing loc entry. **Multiple-angle-bracket
cascades** (`<<key>>`, `<<<key>>>`) is uniquely diagnostic of this shared-
options mutation bug.

### Burned

enemy_tweaker v0.4.0-dev → v0.4.1-dev introduced 3 widgets sharing
`_FACTION_SWAP_OPTIONS`, 6 sharing `_MIMIC_OPTIONS`, 2 sharing
`_BREED_OPTIONS`. User reported `<<<>>>>` brackets on all of them; v0.4.2-dev
fixed by switching to factory functions.

---

## 6. VMF widget `setting_id`s must be globally unique

**Rule:** VMF's `new_mod` validates that every widget in the settings tree
has a unique `setting_id`. The check is **global across all groups/sub-groups**,
not per-parent. Duplicates produce:

```
[MOD][<mod>][ERROR] [VMF Mod Manager] (new_mod) mod options initialization:
could not initialize mod's options. Widgets N and M have the same setting_id
("...").
```

Result: the mod's **entire settings page disappears** — not just the duplicate
widget. `mod:get(setting_id)` still reads the stored value, so runtime logic
isn't broken, but the user has no UI to change settings.

### Implication

You **cannot** have one setting (boon, talent, behavior toggle) appear in two
different category groups in the settings menu using the same `setting_id`.
To get "show this boon under both Defensive>Health AND Orbs", options are:

1. **Single-home only** — pick one category; flag the mechanic family in the
   display name (e.g., `[Orb] Health Orbs`).
2. **Shadow setting + mirror callback** — register a second setting (e.g.,
   `disable_boon_health_orbs__orb_view`) and write an `on_setting_changed`
   callback that copies the value between the primary and the shadow.
   Doubles per-boon plumbing; can drift if the callback errors.
3. **Engineered duplicate** — bypass VMF's validator by patching
   `VMFMod.create_options` or registering options without going through
   `new_mod`. Fragile, breaks on VMF updates.

### How to apply

When designing a settings tree, plan one canonical home per `setting_id`.
For cross-cutting axes (mechanic vs effect, family vs trigger), use display-
name prefixes or a separate flat "filter view" group that exposes a different
toggle.

### Burned

ct v0.7.26-test (2026-05-15). Adding a second `disable_boon_health_orbs`
widget in `disable_boon_healing_and_sustain_group` broke options init;
reverting fixed it. Found while exploring a multi-category Mix design for the
boon menus.

---

## 6a. VMF widget type whitelist

**Rule:** Every widget in a mod's `*_data.lua` settings tree must use a
`type` value from VMF's canonical whitelist. There are exactly **six** valid
types as of VMF current:

| `type` | Use it for |
|---|---|
| `group` | Container that nests `sub_widgets` under a collapsible header. The top-level "Tweaker Settings" tree is always a `group`. Use nested `group`s to organize per-feature toggles into categories. |
| `header` | Static section label inside a `group`. No `default_value`; purely visual. Use sparingly — the `group`'s own title usually suffices. |
| `checkbox` | Boolean toggle. `default_value` is `true` / `false`. The most common widget type — every per-feature on/off toggle in the repo is a `checkbox`. |
| `dropdown` | Single-select from a fixed list. Requires `options = { { text = "Display", value = "internal_key" }, ... }`. Use for enum-like settings (talent-swap picks, preset event mutator picks). |
| `numeric` | Number input with `range = { min, max }` (inclusive) and `default_value` as a number. Use for offsets / scales / percentages / level overrides. Replaces what DMF calls `percent_slider` / `value_slider` — VMF has no `slider` type. |
| `keybind` | Single keybind. `default_value` is a string keycode (or `""` for no-bind). VMF handles capture / unbind / save. Use for any feature that wants a hotkey (camera toggle, freecam, loadout shortcuts). |

Anything outside this whitelist **breaks the mod's entire options page at
load time.** VMF validates widget types strictly and refuses to register
the settings tree if any widget fails the type check. The mod itself still
loads; runtime `mod:get(setting_id)` still reads stored values; only the UI
disappears. See `docs/BUG_CLASSES.md § 18` for the full symptom / diagnosis
write-up.

### Common false-friend types (NOT valid in VMF)

| Wrong type | Why authors reach for it | Use instead |
|---|---|---|
| `text_input` / `string` | Free-text input. DMF has analogous types; VMF does not. | No widget — drive the setting via a `mod:command(...)` chat handler that calls `mod:set(setting_id, text)`. The user types e.g. `/gt_lobby_motd_set Hello world` and the mod stores it. Leave a comment in the `_data.lua` at the would-be widget site explaining the absence. |
| `slider` / `percent_slider` / `value_slider` | Range / percent picker. DMF has all three; VMF folds the same UX into `numeric` with a `range`. | `numeric` with `range = { 0, 100 }` (or whatever min/max applies) and `default_value` as a number. |
| `radio` / `multiselect` | Multi-option picker. Not in VMF. | `dropdown` for single-select. For multi-select, fan out one `checkbox` per option. |
| `description` | Static descriptive text block. DMF has it; VMF doesn't expose a standalone description widget. | Put the explanatory text in the `tooltip` of the nearest widget (every widget supports `tooltip = mod:localize(<key>_tooltip)`), or in the group's own label. |
| `mod_toggle` | Master on/off (DMF). | In VMF, the mod is its own toggle via `is_togglable = true` on `new_mod`. No widget needed. |

### How to apply

When adding a new widget, copy from a known-valid example in this repo's
existing `*_data.lua` files (`career_tweaker_data.lua` and
`cosmetics_tweaker_data.lua` use every active type). If the desired
interaction has no VMF equivalent, drive it via chat command instead of
inventing a widget type.

The static check `qa/check_vmf_widget_types.ps1` (wired into
`qa/run_all.ps1 -Quick` + pre-commit hook) hard-fails any widget whose
`type` is outside the whitelist. There is **no inline suppression pragma**
— invalid types are never acceptable; the static check catches the class
before it ships. Fixtures at `qa/_test_fixtures/widget_type_bad.lua` +
`widget_type_good.lua`.

### Worked examples

```lua
-- checkbox: on/off toggle
{
    setting_id    = "noclip_enabled",
    type          = "checkbox",
    default_value = false,
    tooltip       = mod:localize("noclip_enabled_tooltip"),
},

-- numeric: bounded number with default
{
    setting_id    = "fov_override",
    type          = "numeric",
    default_value = 75,
    range         = { 30, 140 },
    tooltip       = mod:localize("fov_override_tooltip"),
},

-- dropdown: single-select from fixed list
{
    setting_id    = "talent_swap_dr_ironbreaker",
    type          = "dropdown",
    default_value = "none",
    options       = _talent_swap_options(),  -- builds { { text=, value= }, ... }
},

-- keybind: single hotkey
{
    setting_id    = "freecam_toggle",
    type          = "keybind",
    default_value = "f8",
},

-- group: nests sub_widgets
{
    setting_id  = "lobby_group",
    type        = "group",
    sub_widgets = {
        { setting_id = "kick_on_idle", type = "checkbox", default_value = false },
        { setting_id = "idle_seconds", type = "numeric",  default_value = 60, range = { 10, 300 } },
    },
},

-- header: static label inside a group
{
    setting_id = "boon_category_health",
    type       = "header",
},
```

### Burned

general_tweaker v0.2.60-dev (2026-05-25). Author added
`type = "text_input"` for `gt_lobby_motd_text` (assuming VMF had a free-text
widget because DMF does). Widget #103 failed VMF validation and gt's
entire options menu disappeared on user's machine. Fix: deleted the widget,
left a comment at the site explaining the absence, drove the setting via
`/gt_lobby_motd_set <text>` chat command. Static check
`qa/check_vmf_widget_types.ps1` added in the same session to catch the
class going forward.

---

## 7. VMF mod `_localization.lua` is NOT registered into global `Localize`

**Rule:** Strings registered in a mod's `_localization.lua` (via
`mod_localization` in `new_mod()`) are accessible only through
`mod:localize(key)`. They are **NOT** injected into the global `Localize()`
function that vanilla VT2 code uses. If vanilla code calls
`Localize(your_key)`, it returns `<your_key>` (the missing-key placeholder
format).

### Why

VMF's per-mod localization is a private lookup, not a global registration.
`mod:localize(key)` reads from `mod._localization`. The vanilla `Localize`
global doesn't know about VMF's per-mod tables; it reads from engine-bundled
localization files plus official-engine-API extensions.

This split works fine for VMF settings widgets (which use `mod:localize`
internally for labels and descriptions) but **fails** for any string vanilla
code reads via `Localize`:

- Pickup popup `hud_description` (`interaction_ui.lua:684` →
  `Localize(title_text)`)
- Item display names (vanilla `Localize(item.display_name)`)
- HUD action descriptions
- Any string in a vanilla data table fed through `Localize`

### How to apply

For HUD / pickup / interaction strings, add an explicit handler in the mod's
`_G.Localize` hook:

```lua
local _hud_strings = {
    cwv_interaction_ammunition_javelin = "Tuskgor Javelin",
    -- add more keys here as new pickups are added
}

mod:hook(_G, "Localize", function(func, key)
    -- earlier handlers (display names, conditional renames, ...)
    if _hud_strings[key] then
        return _hud_strings[key]
    end
    return func(key)
end)
```

The `_localization.lua` entry is harmless to keep (works for VMF settings
widgets) but is dead code for the HUD / Localize path.

### Burned

Tuskgor Javelin pickup popup, character_weapon_variants v0.1.190 → v0.1.199
(2026-05-09). Added `cwv_interaction_ammunition_javelin = { en = "Tuskgor Javelin" }`
to `_localization.lua`, set `Pickups.ammo[...].hud_description = "cwv_interaction_ammunition_javelin"`,
popup displayed `<cwv_interaction_ammunition_javelin>`. Fixed by adding the
key to the existing `_G.Localize` hook handler.

Likely to recur for: any new pickup, custom interaction prompt text, custom
item display names, custom buff names, custom hat/skin names — anything
vanilla reads from a data field via `Localize`.

---

## 8. `custom_gui_textures` — nested table format and ui_renderer_creator keys

**Rule:** When registering custom GUI textures via VMF, `custom_gui_textures`
goes in the `_data.lua` return table (NOT in the `.mod` file), and
`ui_renderer_injections` MUST use **nested tables** — a flat list of strings
is silently skipped with no error, no log.

### Correct format

```lua
custom_gui_textures = {
    textures = {
        "texture_name_1",
        "texture_name_2",
    },
    ui_renderer_injections = {
        {                                      -- MUST be a nested table
            "ingame_ui",                       -- ui_renderer_creator (required string)
            "materials/ui/my_material_1",      -- material paths
            "materials/ui/my_material_2",
        },
    },
},
```

VMF iterates entries and checks `type(entry) == "table"`. A flat list of
strings is silently skipped. This was the root cause of the v0.7.37 → v0.7.50
portrait investigation.

### `ui_renderer_creator` values

VMF uses `debug.traceback()` to extract the filename (no path/extension) of
the script that called `UIRenderer.create`. Valid values:

- `"ingame_ui"` — main HUD/game renderer (most common, for portraits/gameplay UI)
- `"hero_view"` — hero selection screen
- `"loading_view"` — loading screens
- `"chat_manager"` — chat UI
- `"popup_manager"` — popup dialogs
- `"splash_view"` — splash screen
- `"rcon_manager"`, `"disconnect_indicator_view"`, `"twitch_icon_view"`

Add multiple entries to inject into multiple renderers. Portrait / character
mods need at minimum `ingame_ui` + `ingame_ui_settings` + `level_end_view_base`
+ `level_end_view_versus`; missing `ingame_ui_settings` causes a pause-menu
crash (see `reference_vmf_renderer_creator_keys` in memory).

### Working examples

**InventoryFavorites:**
```lua
ui_renderer_injections = {
    { "ingame_ui", "materials/InventoryFavorites/trash", "materials/InventoryFavorites/heart" },
},
```

**Loremaster's Armoury** (injects into 9 different renderers):
```lua
ui_renderer_injections = {
    { "ingame_ui",      "materials/Loremasters-Armoury/armoury_atlas" },
    { "hero_view",      "materials/Loremasters-Armoury/armoury_atlas" },
    { "loading_view",   "materials/Loremasters-Armoury/armoury_atlas" },
    -- ...
},
```

### What VMF does with this

1. `textures` entries → registered in `_custom_none_atlas_textures`
   (UIAtlasHelper returns false for atlas; UI uses material name directly).
2. `ui_renderer_injections` entries → for each `{creator, materials...}`,
   calls `vmf.inject_materials(mod, creator, materials...)` which destroys
   and recreates the target UIRenderer with the new materials.
3. `atlases` (optional) → for atlas-based textures with UV coordinates.

### Architecture notes

- `UIRenderer._injected_material_sets` is a **separate mechanism** from VMF's
  `inject_materials` — independent systems. Do NOT touch
  `_injected_material_sets` directly: if the engine can't resolve a material
  path when `UIRenderer.create` runs, it silently poisons the **entire** Gui
  material loading pass — ALL materials (including VMF's `vmf_atlas` and
  other mods' atlases) fail to load. See `cosmetics_tweaker` section in
  `DEVELOPMENT.md`.
- VMF's hook on `UIRenderer.create` fires at game boot (VMF inits before
  game scripts).
- Each `.material` file creates ONE Gui material named after the filename
  (not per-definition).
- `Gui.create_material` and `Gui.create` do NOT exist in VT2 — materials
  only at creation time.

### Detecting injected materials at runtime

- Do NOT hook `UIRenderer.create` to set a flag — VMF destroys+recreates the
  renderer internally, so your hook never fires.
- Probe the Gui directly: `Gui.material(gui, material_name)` returns the
  material object or nil.
- Use a `_collect_all_guis()` helper to find gui handles from
  `Managers.ui`, `ingame_ui`, `hud`, `unit_frames`.
- Cache the result in a flag after first successful probe to avoid per-frame
  `Gui.material` overhead.

### VMF source references

- `custom_textures.lua` (14D9427F4BBBDCFE) — `inject_materials`,
  `UIAtlasHelper` hooks
- `vmf_mod_manager.lua` (FA3F694D1916D375) — processes `custom_gui_textures`
  from data file

---

## 9. Debug Logging toggle (universal convention)

**Rule:** every mod in this repo exposes a single `enable_debug_logging`
checkbox at the BOTTOM of the widget tree (un-nested), and gates all verbose
diagnostic prints behind a file-local `_dbg` helper that reads
`mod:get("enable_debug_logging")`. Established 2026-05-25 after user feedback
that the debug toggles across the 16 active mods were inconsistent (some used
`debug_mode`, some `wt_debug_mode`, some `cwv_debug_mode`, some `debug_dumps`,
some none at all).

The authoritative spec is in `PROJECT_STANDARDS.md` § 3.6 — exact `setting_id`,
default, localization string, tooltip text, position rule, helper pattern.
Don't recapitulate it here; treat that section as binding.

### Quick reference

```lua
-- _data.lua — at the BOTTOM of options.widgets, NOT inside a group
{
    setting_id    = "enable_debug_logging",
    type          = "checkbox",
    default_value = false,
    tooltip       = mod:localize("enable_debug_logging_tooltip"),
},
```

```lua
-- _localization.lua
enable_debug_logging         = { en = "Debug Logging" },
enable_debug_logging_tooltip = {
    en = "Emit detailed diagnostic logs to %APPDATA%\\Fatshark\\Vermintide 2\\console_logs\\. Increases log volume; enable when investigating a bug, then disable.",
},
```

```lua
-- <mod>.lua near the top of file (two-helper policy 2026-05-25; see
-- PROJECT_STANDARDS.md § 3.6 "Two-channel discipline" for the full
-- decision matrix + classifier word lists.)
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

`_dbg` is for confirmation / expected behavior (log file only). `_dbg_alert`
is for unexpected / wrong / mismatch (log file AND in-game chat). Both gate
on the same `enable_debug_logging` toggle. For the decision matrix +
call-site classification rules + judgment-call examples, see
**PROJECT_STANDARDS.md § 3.6**.

### Why

Friction. Before the convention every mod's debug toggle lived somewhere
different, was named something different, and the user had to hunt for it per-
mod when chasing a bug. Universal key + universal position = "toggle the
bottom box, send logs."

### Anti-patterns

- Per-mod prefix on the key (`wt_enable_debug_logging`) — same key everywhere.
- Nesting under `group` / `Advanced` / `Misc` / `Developer` — top-level only,
  at the bottom.
- Cluttering the gate body with mod-specific names — the gate is always
  `mod:get("enable_debug_logging")`.

### Burn history

The pre-2026-05-25 state was the burn: across 16 mods, only 5 had any debug
toggle at all (`wt_debug_mode`, `cwv_debug_mode`, `gt_debug_mode`,
`debug_mode` for cim, `debug_dumps` for cosmetics_tweaker) and each lived in
a different position in the widget tree. The 2026-05-25 sweep renamed all
five and added the toggle to the eleven mods that lacked it.

## 10. RPC schema versioning — explicit version + drop-on-mismatch

**Rule:** every mod that defines its own RPCs via `mod:network_send` /
`mod:network_register` declares a `<MOD>_RPC_SCHEMA = N` constant near
`MOD_VERSION`. The constant is prepended as the FIRST positional argument of
every `mod:network_send` the mod emits, and validated as the first argument
of every `mod:network_register` callback. On mismatch, the receiver drops the
message and logs `_dbg_alert("[rpc:schema] <channel> mismatch ...")`. No state
mutation, no crash — graceful degradation.

Established 2026-05-25 as the pilot in chaos_wastes_tweaker v0.7.114-dev
(GitHub Issue #27, Wave-2 net-hardening alongside Issue #28's bt net_replay
ring buffer). Follow-up Issues propagate the pattern to the other RPC-bearing
mods in the repo: cosmetics_tweaker (4 RPCs), lobby_tweaker, enemy_tweaker,
crafting_in_modded, general_tweaker. Don't propagate eagerly — each is a
separate Issue so cross-mod churn doesn't compound.

### Bug class this prevents

Implicit-schema RPCs corrupt receiver state when peers disagree on payload
shape. With multi-build-per-day dev iteration, the chance of a host running a
new dev bundle while a friend runs a stale Workshop bundle (or vice versa) is
high. Symptoms before the gate: client receives the host's broadcast, parses
its positional args by position, writes the wrong field types into local
state, mod misbehaves in confusing ways with no log trace pointing at the
real cause. Symptom after the gate: `[rpc:schema] <channel> mismatch from
peer=<peer>: peer sent v<n>, we expect v<our>. Dropping.` — bug surfaces at
the first mismatch, not 30 minutes downstream.

### Quick reference

```lua
-- Near MOD_VERSION:
-- Bump ONLY when changing RPC payload shape (add/remove/reorder fields).
-- Initial value is 1; never define it lower.
local CT_RPC_SCHEMA = 1

-- Every sender:
mod:network_send("ct_sync_host_settings_chunk", "others",
    CT_RPC_SCHEMA,                     -- FIRST positional arg, always
    session, seq, total, chunk_str)    -- existing payload follows

-- Every receiver:
mod:network_register("ct_sync_host_settings_chunk",
    function(sender_peer_id, schema_version, session, seq, total, chunk_str)
        if schema_version ~= CT_RPC_SCHEMA then
            _dbg_alert("[rpc:schema] %s mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
                "ct_sync_host_settings_chunk", tostring(sender_peer_id),
                tostring(schema_version), CT_RPC_SCHEMA)
            return
        end
        -- ...normal handling...
    end)

-- Regression check (per mod):
_rt_register("ct_rpc_schema_present", function()
    if type(CT_RPC_SCHEMA) ~= "number" then
        return "CT_RPC_SCHEMA not defined as number"
    end
    if CT_RPC_SCHEMA < 1 then return "CT_RPC_SCHEMA < 1" end
end)
```

### When to bump

Bump `<MOD>_RPC_SCHEMA` when ANY of the following changes:

- A field is added to the payload of any RPC the mod defines.
- A field is removed from the payload of any RPC the mod defines.
- The positional order of fields changes.
- The TYPE of an existing positional field changes (e.g. number → string).

Do NOT bump for:

- Adding a new RPC channel with no callers on old peers (old peers won't have
  the handler registered; old senders won't send the channel — naturally
  cross-version safe via VMF's "unknown channel = no-op" behavior).
- Renaming a channel (same as adding new + removing old — old senders use
  the old channel name; new senders use the new one; no positional drift).
- Logging-only changes (the gate is positional, log lines are post-gate).
- Refactoring the handler body without changing positional args.

### Adding a NEW RPC after the pattern lands

The new RPC participates in the same `<MOD>_RPC_SCHEMA` value as every other
RPC the mod defines — there's only one constant per mod, shared across all
the mod's channels. Adding a new RPC does NOT itself bump the constant, but
the new sender MUST prepend `<MOD>_RPC_SCHEMA` and the new receiver MUST gate
on it the same way. The first time a future shape change lands on that
channel, the constant bumps for the whole mod.

### Graceful-degradation behavior (cross-version)

- **New peer → old peer**: new sender includes the version arg; old receiver
  doesn't expect it, sees the version in its `session` (or whichever-was-
  first) slot, type-checks fail → old receiver drops. The old receiver still
  silently fails on its own type checks; this is acceptable because old
  receivers don't have the gate yet and the schema gate IS the migration
  cliff. New behavior: clean drop with a useful log line.
- **Old peer → new peer**: old sender omits the version arg; new receiver
  sees its first real payload field (e.g. a number `session`) in the
  `schema_version` slot. The compare `payload_field ~= CT_RPC_SCHEMA` almost
  always fails → new receiver logs `[rpc:schema]` mismatch and drops. Worst
  case: a peer's session id happens to numerically equal `CT_RPC_SCHEMA`
  (very unlikely; session ids are millisecond timestamps modulo 2^31). The
  defensive type-checks AFTER the schema gate catch this — the legacy first
  arg's type matched the schema_version slot but later args are off by one
  and fail their type checks.

Both paths end in a clean drop. No state corruption.

### Anti-patterns

- **Per-RPC schema versions.** Don't ship `CT_RPC_SCHEMA_SETTINGS` and
  `CT_RPC_SCHEMA_GRAPH` separately. One constant per mod is enough — bumping
  it because one RPC's shape changed temporarily tightens the gate on the
  others too, which is the desired pessimistic behavior (a mod that touched
  one wire shape might have invisibly touched another).
- **Cross-mod shared schema constant.** Don't define a repo-wide
  `RPC_SCHEMA` and have every mod read it. Each mod's RPCs are scoped to
  that mod; bumping one mod's payload shouldn't force a chain bump on the
  others.
- **Skipping the gate on "internal" RPCs.** Every `mod:network_register`
  callback the mod owns gets the gate. The receiver-side cost is one
  equality compare; the sender-side cost is one extra positional arg. There
  is no scenario where the gate is too expensive to be worth it.
- **Returning an error from the gate.** Drop and log — don't `error()` or
  `mod:warning()`. A noisy chat error every RPC tick from a stale peer is
  worse than the silent corruption it replaces. Use `_dbg_alert` so it
  surfaces in chat when debug logging is on, and to the log file
  unconditionally.

### Burn history

This is preventive: no recorded burn yet (the pattern landed before a real
cross-version desync triggered the implicit-schema corruption class). The
2026-05-19 desync investigation (host vs client running unconfirmed-different
builds, three-peer graph divergence) was the prompt — the post-mortem
couldn't rule out implicit-schema drift because there was no gate to confirm
peers were on the same wire shape.

### See also

- `chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/chaos_wastes_tweaker.lua` —
  search for `CT_RPC_SCHEMA` for the canonical pilot implementation across
  all three of ct's RPCs.
- `chaos_wastes_tweaker/CHANGELOG.md` v0.7.114-dev — the pilot bump entry,
  including the follow-up-Issues list.
- GitHub Issue #27 — original spec.
- GitHub Issue #28 — bt net_replay ring buffer (sibling MP hardening).

## 11. Per-hook perf timing via bt.perf_record (experimental — Wave 2)

**Status: experimental.** Framework installed in `buff_tweaker` (bt) v0.1.6-alpha (2026-05-25). Adoption by other mods is opt-in per-mod (no migration yet). Don't propagate eagerly — add the `bt.perf_record` call to a mod's `mod:safe_hook` bodies only when you have a specific perf question for that mod.

### Why bt

Per `CLAUDE.md`'s "Mod Directory" table, `buff_tweaker` is the shared infra mod (originally just the BR registry, now also `net_replay` per VMF_RECIPES § 10, the `perf_record` accumulator per this section, and any future shared-instrumentation surface). Consumer mods reach it via the standard `get_mod("bt")` pattern; if bt isn't installed the calls return nil and the timing helpers silently no-op.

### API

```lua
-- In any consumer mod:
local bt = get_mod("bt")
if bt and bt.perf_record then
    local t0 = os.clock()
    -- ... the work to time ...
    bt:perf_record("<mod_id>", "<Class.method or label>", (os.clock() - t0) * 1000)
end
```

Per-call cost: one nested-table access + three field updates. Safe on warm paths; rate-limit yourself before adopting on per-frame hooks.

### /perf_dump chat command

```
/perf_dump
=== /perf_dump (top N of M entries) ===
[<mod_id>] <class.method> count=N total=Xms avg=Yms max=Zms
...
```

Sorts entries by `total_ms` descending; top 20 shown in chat, all 20 also mirrored to `mod:info("[bt:perf_dump] ...")` for offline diff. Empty state: `/perf_dump: no records yet -- adopt mod.perf_record in your safe_hook bodies.`

### Example: wiring a safe_hook body for timing

```lua
local bt = get_mod("bt")

mod:safe_hook("GearUtils", "create_equipment", function(func, ...)
    local t0 = os.clock()
    local res = func(...)
    if bt and bt.perf_record then
        bt:perf_record("<mod_id>", "GearUtils.create_equipment", (os.clock() - t0) * 1000)
    end
    return res
end)
```

Cache the `bt` reference at file scope to avoid the `get_mod` lookup on every fire:

```lua
local _bt = get_mod("bt")
local _bt_record = _bt and _bt.perf_record and function(class_method, elapsed_ms)
    _bt:perf_record("<mod_id>", class_method, elapsed_ms)
end or function() end  -- no-op if bt isn't installed
```

Then in the hook: `_bt_record("GearUtils.create_equipment", elapsed_ms)`.

### When to use vs not

USE perf_record when:
- Investigating "is this hook hot?" without a profiler.
- Comparing perf impact of two hook strategies (safe_hook vs traced_hook vs raw hook).
- Tracking a specific hook over a long session to see how it scales with party size / Chaos Wastes depth / boon count.

DON'T USE perf_record when:
- The hook fires at 60+ Hz on a hot frame path. `os.clock()` is cheap but not free; the accumulator update adds three field writes per call. Sample instead (every Nth call) or move to a periodic histogram dump.
- You're trying to time something narrower than a single function call. perf_record is for hook-grain timing, not micro-benchmarking.

### Anti-patterns

- **Don't gate `perf_record` calls behind `enable_debug_logging`.** The point is always-on hook timing; the gate is on `/perf_dump` (user-initiated read), not on the writes. If you want a debug-only perf dump, write your own gated wrapper.
- **Don't introduce a per-mod copy of the accumulator.** The whole point of putting it in bt is one shared registry the user can `/perf_dump` from any mod's hooks. Cross-mod perf comparisons are the load-bearing use case.
- **Don't propagate to every mod's every hook in one PR.** The bt framework landed in 0.1.6-alpha with ONE example consumer (bt's own `on_all_mods_loaded` time). Other mods adopt the helper one at a time, motivated by a specific perf question — not as a mass migration.

### Burn history

Preventive. No recorded burn yet — landed alongside the universal applied-marker rollout (PROJECT_STANDARDS § 3.6) as the experimental Wave 2 sibling. Adoption catalog will accumulate here as mods opt in.

### See also

- `buff_tweaker/scripts/mods/buff_tweaker/buff_tweaker.lua` — the canonical `_perf_state` + `mod.perf_record` + `/perf_dump` implementation. Search for `_perf_state` for the table layout and `mod:command("perf_dump", ...)` for the dump format.
- `buff_tweaker/CHANGELOG.md` v0.1.6-alpha — the install entry.
- `PROJECT_STANDARDS.md` § 3.6 — "Applied marker line (universal)" — sibling hardening pattern landed same day.

---

## 12. Stingray `event:register` signature — 3rd arg MUST be a string method name

**Rule:** Stingray's per-state `EventManager:register(target_object, event_name, callback_name)` resolves the callback BY NAME against `target_object` at fire time — it does `target_object[callback_name](target_object, ...)` from C++. The 3rd arg MUST be a string method name (or a string identifying a function field on the object). Passing a function VALUE (`em:register(mod, "ev", _local_fn)`) makes the engine try to index `mod[<function>]` and emits:

```
[Script Error] (script) ... No function found with name '[function]'
```

The handler never fires and the feature silently dies.

### Why

This is `Managers.state.event` (the per-state EventManager) — NOT `mod:hook` (VMF wrapper) and NOT `mod:command` (VMF chat). The EventManager is a vanilla Stingray API; its `register` method accepts `(object, event_name, callback_name)` where the third arg is fed straight into a C++ `object:method_by_name(callback_name, ...)` call at fire time. There is no function-value fallback path. VMF doesn't wrap or sanity-check this; you reach through `Managers.state.event` directly.

### How to apply

**Canonical form** — assign the function to the target object under a method name, then register with the matching STRING:

```lua
local mod = get_mod("my_mod")

local function _on_player_joined_party(self, peer_id)
    -- self == mod (Stingray invokes target_object:method_name(...))
    -- peer_id is the joiner
end

-- Assign as a method (the receiver is conventionally `self == target_object`).
mod.my_mod_on_player_joined_party = _on_player_joined_party

-- Register with the STRING name.
local em = Managers.state and Managers.state.event
if em then
    em:register(mod, "on_player_joined_party", "my_mod_on_player_joined_party")
end
```

**Wrong forms** (the static check `qa/check_event_register_signature.ps1` flags all of these as hard errors — no suppression pragma):

```lua
em:register(mod, "ev", _on_player_joined_party)   -- local function value
em:register(mod, "ev", function() ... end)         -- inline function value
em:register(mod, "ev", some_table.method)          -- function field deref
```

### Naming convention

Prefix the method name with the mod's short id (`gt_lobby_motd_on_player_joined_party`, `my_mod_on_player_joined_party`) so two mods registering against the same event don't pick the same method name on a shared `target_object`. The method name is namespaced on the target object, not globally — two mods that each pass their own `mod` table as `target_object` don't collide, but if you ever register against a shared object (e.g. a vanilla manager), the namespacing matters.

### State-event lifecycle

`Managers.state.event` is REBUILT on every state transition (StateInGame, StateLoading, StateTitleScreen). Re-register on every fresh handle — gt's pattern is to compare the live `Managers.state.event` against a cached `_last_state_event` upvalue in a per-tick update callback and re-register when they differ. See `general_tweaker/scripts/mods/general_tweaker/_gt_lobby_motd.lua:222-235` for the canonical wiring (and the immediate-call branch at line 239-243 for hot-reload mid-mission).

### bt runtime adapter (optional safety net)

`buff_tweaker` (bt) v0.1.10-alpha+ ships `mod:safe_event_register(em, target_object, event_name, method_name_or_fn)` as an optional adapter. It accepts either the canonical string or a function value (auto-adapts the function by assigning it to `target_object` under a generated `_bt_evreg_<event>_<counter>` name), logs an `[ALERT]` line with the caller's source-file/line via `debug.getinfo(3, "Sl")` so the next session can grep the log even when the bug self-heals.

```lua
local bt = get_mod("bt")
if em and bt and bt.safe_event_register then
    bt:safe_event_register(em, mod, "on_player_joined_party",
                           "my_mod_on_player_joined_party")
end
```

The adapter is the safety net, NOT the primary fix. Consumer mods must still wire the correct string-method pattern themselves so the code is correct even when bt isn't installed.

### Burn history

Four separate gt fixes on 2026-05-25 — v0.2.61 / .62 / .63 / .64 — all variants of this same bug class across lobby MOTD, session-ignore, and slot-reservations modules. Each shipped with a function value as the 3rd arg, each silently lost the handler, each surfaced as "feature toggle on, in-game nothing happens, log full of `No function found with name '[function]'`".

Static gate landed same-day: `qa/check_event_register_signature.ps1`. Full-tree scan clean post-v0.2.64.

### See also

- `general_tweaker/scripts/mods/general_tweaker/_gt_lobby_motd.lua:222-243` — the canonical state-event re-registration pattern.
- `qa/check_event_register_signature.ps1` — the static check; `qa/_test_fixtures/event_register_{bad,good}.lua` — fixtures.
- `buff_tweaker/scripts/mods/buff_tweaker/buff_tweaker.lua` — `mod.safe_event_register` runtime adapter (search for `safe_event_register`).
- `docs/BUG_CLASSES.md` — entry for this bug class.

## 13. Custom buttons / panels in a hero-view menu — use an own-scenegraph overlay

**Goal:** add clickable buttons (or a popup) to an existing VT2 menu screen (the keep inventory, the crafting forge, a weave window, etc.).

### The WRONG way (burned crafting_in_modded 3×, v0.7.57 → v0.7.64)

Calling `UIWidgets.create_default_button(scenegraph_id, size, ...)` and appending the widget to the **host window's** draw array, anchored to one of the window's existing scenegraph nodes (especially a full-size centre node like `"viewport"` / `"viewport_2"`). Every attempt produced the same three failures:

- **Screen-covering black box** — `create_default_button`'s background rect stretches to fill the *scenegraph node*, and the node was the near-fullscreen viewport. The button's own `size` param does not constrain the background.
- **Corner placement** — anchoring a fixed-size button to a full-size `center`/`bottom`-aligned node lands it in a corner, not where you intended.
- **Overlapping hotspots** — stacked buttons sharing/overlapping the node region → one mouse click fires two of them (e.g. crafted a trinket *and* a charm from one press).

There's also the render-array trap: many hero windows have **no `self._widgets`** — they draw from `_top_widgets` / `_bottom_widgets` / `_top_hdr_widgets` / `_bottom_hdr_widgets`. Appending to `_widgets` renders nothing at all. (Confirm by reading the window's `_draw`.)

### The RIGHT way — own-scenegraph overlay

Build a self-contained module that owns its scenegraph, widgets, draw pass, and input. Canonical examples in this repo:

- **Popup:** `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_glow_picker.lua` (+ its draw/input hooks in `cosmetics_tweaker.lua` ~7076-7116).
- **Embedded button row:** `crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_accessory_craft_panel.lua` (hooked off `HeroWindowWeaveProperties._draw`).

Five steps:

1. **Own scenegraph** — `UISceneGraph.init_scenegraph(def)`, every node with EXPLICIT `position` / `size` / `horizontal_alignment` / `vertical_alignment` / `parent`. Positions are now reliable constants; repositioning is a number edit, not a guess.
2. **Hand-rolled widget defs** — `element.passes = { hotspot, rect (style_id), border, text }`, with `style.rect.size = {W,H}` so the background is the *button* size. NOT `create_default_button`.
3. **Own draw pass** — `UIRenderer.begin_pass(ui_renderer, OWN_scenegraph, input_service, dt, nil, {snap_pixel_positions=true})` → loop `UIRenderer.draw_widget` → `UIRenderer.end_pass`. pcall-guard each call so a UI hiccup can't crash the screen.
4. **Hook the host window's draw** — `mod:hook_safe("HeroWindowX", "_draw" or "draw", fn)`. Resolve the renderer from `self._ui_top_renderer or self._ui_renderer or self.ui_top_renderer or self.ui_renderer` (naming differs per window — underscore vs not), and input from `self._parent:window_input_service()`. Vanilla weave `_draw(self, dt)` passes only `(self, dt)`; `HeroWindowItemCustomization._draw(self, input_service, dt)` passes the service.
5. **Read hotspots after the pass** — `widget.content.hotspot.on_release` per button; set it false to consume (fires once). Distinct nodes ⇒ no double-fire. `hotspot.is_hover` for hover color.

The module file auto-bundles via the package wildcard `lua = ["scripts/mods/<mod>/*"]` — no manifest edit. Add `_rt_register` checks (module loaded + exposes draw + correct button count; state-witness that the lazy build produced N widgets once the screen was opened). See `crafting_in_modded_dev` tests `accessory_panel_module_loaded` / `accessory_panel_built_when_accessories_opened`.

### Duplicate-hook rule still applies

Grep the mod for an existing hook on `("HeroWindowX", "_draw"/"draw"/"update")` before adding yours (§ 1). A second `hook_safe` on the same pair is silently dropped.

### Burned

crafting_in_modded v0.7.57 (overview, timing) → v0.7.58 (timing fixed, still wrong render array) → v0.7.60 (render array fixed, corner + black box) → v0.7.63 (same on the accessories view) → v0.7.64 (disabled) → **v0.7.65 rewrote as an own-scenegraph overlay; worked first try in-game.** Memory: `reference_vt2_menu_button_overlay_pattern.md`.
