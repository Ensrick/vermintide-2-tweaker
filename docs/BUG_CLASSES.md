# BUG_CLASSES.md — catalog of known bug patterns

Quick-reference catalog of bug classes that have actually bitten this repo. When
a user reports a bug, **pattern-match against this list first** — most issues
are repeats of patterns already shipped, debugged, and fixed elsewhere in the
monorepo. Each entry: symptom -> diagnosis pattern -> fix template -> canonical
Issue / commit / CHANGELOG citation.

Adjacent docs:
- `docs/BUG_TRIAGE_RUNBOOK.md` — the workflow that USES this catalog (intake,
  match, fix, verify, document).
- `VMF_RECIPES.md` — full mechanics + burn history for the VMF-side gotchas
  this catalog cross-references.
- `PROJECT_STANDARDS.md` — operational rulebook (§ 9 Anti-patterns mirrors
  several entries below).
- `tools/mod-lint/BUG_PATTERN_CATALOGUE.md` — patterns mineable from history
  that the lint tool either checks or could check.
- `CLAUDE.md` § "High-frequency engine quirks" — short-form bullets on the
  Stingray / Lua 5.1 quirks this catalog expands on.

---

## 1. VMF `hook_safe` silent overwrite (duplicate registration)

**First seen:** 2026-05-07 (cwv v0.1.96 → v0.1.99)
**Canonical Issue:** [#33](https://github.com/Ensrick/vermintide-2-tweaker/issues/33) (cwv `SimpleInventoryExtension.wield` duplicate)
**Lives in:** any `mod:hook_safe(C, m, ...)` call site

### Symptoms
- A `mod:hook_safe` callback "should fire" per install log but its body never runs at runtime.
- Install log shows `Hooking '<method>' from [<Class>]` printed **twice** with identical Origin pointers.
- Feature wired through one of the two registrations silently doesn't work (no error, no warning).
- `tools/mod-lint/lint-mod.ps1` exits with code 2 and lists the duplicate pair.

### Diagnosis pattern
1. Run `tools/mod-lint/lint-mod.ps1 <mod>` — exit 2 means duplicate hook detected.
2. If no lint, grep the mod for `mod:hook_safe.*"<MethodName>"`. Two hits on the same `(Class, method)` pair = bug.
3. Check console_logs for `Hooking '<method>' from [<Class>]` appearing twice.

### Fix template
Consolidate the two callbacks into one. `hook_safe` runs after the original; ordering inside the body is your choice.

```lua
-- WRONG -- second registration silently overwrites the first
mod:hook_safe("SimpleInventoryExtension", "wield", function(self, slot_name)
    _track_cross_access(self, slot_name)
end)
-- ...elsewhere in the file...
mod:hook_safe("SimpleInventoryExtension", "wield", function(self, slot_name)
    _dbg("loadout slot=%s", slot_name)
end)

-- RIGHT -- one callback per (Class, method) per mod
mod:hook_safe("SimpleInventoryExtension", "wield", function(self, slot_name)
    _track_cross_access(self, slot_name)
    if _debug_mode_enabled() then
        _dbg("loadout slot=%s", slot_name)
    end
end)
```

Full mechanic + how to apply: `VMF_RECIPES.md § 1`. Hook policy: `CLAUDE.md § Hooking`.

### Related Issues / commits
- Issue [#33](https://github.com/Ensrick/vermintide-2-tweaker/issues/33) (cwv, 2026-05-25)
- `character_weapon_variants/CHANGELOG.md` v0.1.336+ — consolidation entries
- Original burn: cwv v0.1.96 → v0.1.99, two `PlayerProjectileUnitExtension.init` registrations

---

## 1b. Hook target doesn't exist (silent dead hook)

**First seen:** 2026-05-25 (cosmetics_tweaker `SimpleHuskInventoryExtension.extensions_ready`)
**Canonical Issues:** [#35](https://github.com/Ensrick/vermintide-2-tweaker/issues/35) (cosmetics), [#41](https://github.com/Ensrick/vermintide-2-tweaker/issues/41) (gut `NewsHeadUI` typo)
**Lives in:** any `mod:hook_safe("<global>", "<method>", ...)` against a non-existent target

### Symptoms
- Console log: `[MOD][<mod>][ERROR] (hook_safe): trying to hook object that doesn't exist: <ClassName>`
- One ERROR line per registration at mod-load time (sometimes printed twice if two registrations target the same dead name).
- Feature silently doesn't fire — no runtime warning, no further error.

### Diagnosis pattern
1. Grep the latest console_log for `trying to hook object that doesn't exist`.
2. Each ERROR line names the missing class — grep the mod for `hook_safe.*"<ClassName>"` to find the registration.
3. Check `Vermintide-2-Source-Code/scripts/ui/views/` and `scripts/unit_extensions/` for the current canonical class name (Fatshark refactor may have renamed it; e.g. `NewsHeadUI` → `IngameNewsView`).
4. If the method genuinely doesn't exist on the class (vs. the whole class being missing), the same ERROR shape applies — verify via the decompiled source.

### Fix template
Either rename to the correct target OR delete the dead hook + remove the orphan feature code.

```lua
-- WRONG -- target doesn't exist
mod:hook_safe("NewsHeadUI", "_create_news_feed", function(self) ... end)

-- RIGHT (rename) -- check Vermintide-2-Source-Code for the current name
mod:hook_safe("IngameNewsView", "_create_news_feed", function(self) ... end)

-- RIGHT (delete) -- if the feature is no longer relevant, remove the hook
-- and the body it called; note in CHANGELOG.
```

Note: `safe_hook` (Issue [#26](https://github.com/Ensrick/vermintide-2-tweaker/issues/26)) does NOT catch this class — it protects runtime raises in hook bodies, not registration-time misses against missing targets.

### Related Issues / commits
- Issue [#35](https://github.com/Ensrick/vermintide-2-tweaker/issues/35) (cosmetics_tweaker `SimpleHuskInventoryExtension.extensions_ready`)
- Issue [#41](https://github.com/Ensrick/vermintide-2-tweaker/issues/41) (gui_tweaker `NewsHeadUI` — 2 registrations)

---

## 2. Hook wrapper multi-return collapse

**First seen:** 2026-05-?? (enemy_tweaker v0.2.4)
**Canonical Issue:** [#26](https://github.com/Ensrick/vermintide-2-tweaker/issues/26) (safe_hook wrapper that re-introduced this class)
**Lives in:** any `mod:hook` body wrapping a multi-return vanilla function

### Symptoms
- Downstream caller sees `nil` where a 2nd / 3rd return value should be.
- Engine-side error like `horde_spawner.lua:1060: 'for' limit must be a number` (the wrapped function's 2nd return reached a downstream `for i = 1, num do` as nil).
- Intermittent feature breakage that "worked yesterday" after a hook-body refactor.

### Diagnosis pattern
1. Grep the hook for `return\s+\w+\s*\(\s*func\s*\(` — a single-call `return wrapper(func(...))` pattern.
2. Look up the wrapped function in `Vermintide-2-Source-Code` — count its `return` values. Spawn / composition / `get_loadout` / `get_item_units` functions love returning 2-3.
3. If the source returns N > 1 values and the wrapper only forwards the first → bug.

### Fix template
Capture every return into locals; transform only the one you need.

```lua
-- WRONG -- num_to_spawn collapses to nil at the caller
mod:hook("HordeSpawner", "compose_blob_horde_spawn_list", function(func, self, comp, ...)
    return _apply_breed_swap(func(self, comp, ...))
end)

-- RIGHT -- capture every return, transform what you need
mod:hook("HordeSpawner", "compose_blob_horde_spawn_list", function(func, self, comp, ...)
    local spawn_list, num_to_spawn = func(self, comp, ...)
    return _apply_breed_swap(spawn_list), num_to_spawn
end)
```

Full mechanic + burn history: `VMF_RECIPES.md § 2`. Lint coverage: `tools/mod-lint/BUG_PATTERN_CATALOGUE.md § A2`.

### Related Issues / commits
- enemy_tweaker v0.2.4 — original burn (`HordeSpawner.compose_blob_horde_spawn_list`)
- Issue [#26](https://github.com/Ensrick/vermintide-2-tweaker/issues/26) — `mod:safe_hook` wrapper re-introduced this in v0.12.77 (see § 3 below)

---

## 3. Lua 5.1 `unpack` with nil holes (non-deterministic truncation)

**First seen:** 2026-05-25 (weapon_tweaker v0.12.77 → .78 → .79 fix cycle)
**Canonical Issue:** [#36](https://github.com/Ensrick/vermintide-2-tweaker/issues/36) (static check proposal)
**Lives in:** any `unpack(t, i)` call without an explicit `j`

### Symptoms
- Intermittent feature breakage — sometimes works, sometimes doesn't.
- Worse on melee weapons (or any code path where the source variadic has nil slots at known positions, e.g. ammo-unit positions 2 and 4 in `GearUtils.spawn_inventory_unit`'s 4-tuple).
- Downstream symptoms can be wild: `tostring(math.huge) == "inf"` on ammo HUD, 1P weapon hand not rendered, glow apply silently dropping the second hand.

### Diagnosis pattern
1. Grep for `unpack\([^,)]+\s*\)` or `unpack\([^,)]+,\s*\d+\s*\)` (1- or 2-arg unpack with no `j`).
2. Trace back: where did the table come from? If `local t = { f(...) }` and `f` returns a tuple that may have nils, `#t` is undefined in Lua 5.1.
3. Smoking gun: the same call site behaves differently across runs / different weapon types / different player states.

### Fix template
Capture the real arity via `select("#", ...)` from the source variadic; pass `j` explicitly.

```lua
-- WRONG -- nil holes truncate non-deterministically
mod:safe_hook("GearUtils", "spawn_inventory_unit", function(func, ...)
    local results = { xpcall(handler, _err, func, ...) }
    if results[1] then
        return unpack(results, 2)  -- defaults to j = #results, undefined w/ nils
    end
end)

-- RIGHT -- capture real arity from the variadic, pass j explicitly
local function _capture(...) return select("#", ...), { ... } end
mod:safe_hook("GearUtils", "spawn_inventory_unit", function(func, ...)
    local n, results = _capture(xpcall(handler, _err, func, ...))
    if results[1] then
        return unpack(results, 2, n)  -- explicit j preserves nil holes
    end
end)
```

Full mechanic + canonical 4-return example: `VMF_RECIPES.md § 2a`.
Short-form engine bullet: `CLAUDE.md § High-frequency engine quirks`.
Anti-pattern citation: `PROJECT_STANDARDS.md § 9.9`.

### Related Issues / commits
- Issue [#36](https://github.com/Ensrick/vermintide-2-tweaker/issues/36) — proposes `qa/check_unpack_safety.ps1` static check
- weapon_tweaker v0.12.77 (Issue #26 fix introduced the collapse)
- weapon_tweaker v0.12.78 (first attempt at fix — `unpack(results, 2)` without j, still broken)
- weapon_tweaker v0.12.79 (correct fix — `unpack(results, 2, n)`)

---

## 3b. Stingray `event:register` function-value 3rd arg (silent handler death)

**First seen:** 2026-05-25 (gt v0.2.61 → .62 → .63 → .64 — four-fix burn)
**Canonical static check:** `qa/check_event_register_signature.ps1`
**Lives in:** any `Managers.state.event:register(target, "event_name", X)` call where `X` is a function value instead of a string method name

### Symptoms
- Feature toggle enabled, in-game NOTHING happens, no chat error.
- Console log contains repeated lines:
  ```
  [Script Error] (script) ... No function found with name '[function]'
  ```
- Repeats once per event fire — every player join, every state change, etc.
- Pattern is silent: VMF doesn't log anything; only the engine's C++ event-fire path surfaces the failure (as a `[Script Error]`, not a Lua exception, so `pcall` doesn't catch it).

### Why
Stingray's `EventManager:register(object, event_name, callback_name)` is a vanilla C++ API. At fire time the engine does roughly `object[callback_name](object, ...)` from C++. The third arg MUST be a STRING — there's no function-value fallback path. Passing a function value makes the engine try `object[<function>]`, which is `nil`, and emits the `No function found with name '[function]'` error. VMF doesn't wrap or sanity-check this; you reach through `Managers.state.event` directly.

### Diagnosis pattern
1. Grep the latest console_log for `No function found with name '[function]'`.
2. Each occurrence corresponds to a fire of an event whose registration passed a function value. Grep the affected mod for `:register(`. Any 3-arg call whose third arg isn't a quoted string is the bug.
3. Verify with `qa\check_event_register_signature.ps1` — it scans every active mod and hard-fails (exit 2) on any non-string 3rd arg.

### Fix template
Assign the function to `target_object` under a method name, register with the STRING.

```lua
-- WRONG -- engine logs "No function found with name '[function]'" per fire
local function _on_player_joined_party(peer_id)
    -- ...
end
em:register(mod, "on_player_joined_party", _on_player_joined_party)

-- RIGHT -- function lives as a method on mod; register the matching string
local function _on_player_joined_party(self, peer_id)
    -- self == mod (Stingray invokes target:method_name(...))
    -- ...
end
mod.my_mod_on_player_joined_party = _on_player_joined_party
em:register(mod, "on_player_joined_party", "my_mod_on_player_joined_party")
```

State-event lifecycle: `Managers.state.event` is REBUILT on every state transition (StateInGame, StateLoading, StateTitleScreen). Re-register on every fresh handle via a per-tick update callback that compares the live `Managers.state.event` against a cached upvalue. Canonical wiring: `general_tweaker/scripts/mods/general_tweaker/_gt_lobby_motd.lua:222-243`.

Full mechanic + naming convention: `VMF_RECIPES.md § 12`. The live mitigation is the static check `qa/check_event_register_signature.ps1` (hard-fail, no suppression). The former `bt:safe_event_register` runtime safety net is RETIRED (bt archived 2026-06; `get_mod("bt")` always nil) — it was only ever an optional adapter, never the primary fix.

### Related Issues / commits
- gt v0.2.61 (`_gt_lobby_motd.lua` — first fix; on_player_joined_party MOTD)
- gt v0.2.62 (`_gt_lobby_session_ignore.lua` — second fix; session-ignore join filter)
- gt v0.2.63 (`_gt_lobby_slot_reservations.lua` — third fix; slot reservation enforcement)
- gt v0.2.64 (additional sites missed in .61-.63 — final pass)
- bt v0.1.10-alpha — `mod.safe_event_register` runtime adapter landed (RETIRED 2026-06 with bt; no longer available)
- New static check: `qa/check_event_register_signature.ps1` (Quick mode) — the live, canonical gate

---

## 4. Missing `rawget` on fragile globals (`__index` exception spam)

**First seen:** 2026-05-24 (cwv v0.1.332 → v0.1.333)
**Canonical Issue:** [#20](https://github.com/Ensrick/vermintide-2-tweaker/issues/20)
**Lives in:** any cold read like `ItemMasterList[key]`, `NetworkLookup.weapon_skins[key]`, `NetworkLookup.breeds[name]` used as the LHS of a boolean test

### Symptoms
- Console log fills with `[Lua] <<crashify-exception>>` blocks on every keep load (CWV burned with 27 per load, one per variant key).
- Crashify exception text reads `<<system>>[ItemMasterList]<</system>>` `<<message>>ItemMaster List has no item <key><</message>>`.
- Functionality may still appear to work — the `if not X[key] then X[key] = ... end` write branch executes correctly. The bug is purely the noise on the read side.
- Severe variant: peer late-join / DLC-not-owned / gated-registration mismatch hits a missing key cold read in critical-path code → outright crash, not just exception spam.

### Diagnosis pattern
1. Grep latest console_log for `crashify-exception` + `<<system>>[ItemMasterList]<</system>>` (or `[NetworkLookup.<table>]`).
2. The crashify message names the missing key; grep the mod for `<MasterTable>\[` (e.g. `ItemMasterList\[`) used as boolean LHS.
3. Confirm by reading the table's `__index` metamethod in `Vermintide-2-Source-Code` — strict-lookup tables install an `__index` that calls `crashify.print_exception` on missing key.

### Fix template
Wrap reads in `rawget` to bypass the metamethod.

```lua
-- WRONG -- triggers __index metamethod -> crashify.print_exception
if not ItemMasterList[key] then
    ItemMasterList[key] = _build_entry(key)
end

-- RIGHT -- rawget bypasses __index
if not rawget(ItemMasterList, key) then
    ItemMasterList[key] = _build_entry(key)
end
```

Same pattern applies to `NetworkLookup.breeds`, `NetworkLookup.weapon_skins`, `NetworkLookup.damage_profiles`, `NetworkLookup.pickup_names`, `NetworkLookup.item_names`, `CareerSettings`, `DLCSettings`.

Hook policy + failure-mode table: `CLAUDE.md § Hooking → rawget for fragile globals`. Lint coverage: `tools/mod-lint/BUG_PATTERN_CATALOGUE.md § A3`.

### Related Issues / commits
- Issue [#20](https://github.com/Ensrick/vermintide-2-tweaker/issues/20) — 27 ItemMasterList crashify exceptions (CWV v0.1.332)
- Issue [#8](https://github.com/Ensrick/vermintide-2-tweaker/issues/8) — wt: defensive rawget on user-input ItemMasterList lookups
- enemy_tweaker v0.2.2 → v0.2.4 — earlier burn on `NetworkLookup.breeds`

---

## 5. Self-owned vs husk extension class confusion

**First seen:** scoped under Issue [#35](https://github.com/Ensrick/vermintide-2-tweaker/issues/35) (cosmetics dead hook on husk-side method)
**Canonical Issue:** noted in `CLAUDE.md § Hooks that silently no-op`
**Lives in:** any hook on `Simple*Extension` or `SimpleHusk*Extension`

### Symptoms
- Feature works for the **local player** but not for **remote players in MP** (or vice versa).
- Hooked-class install log entry shows the hook installed cleanly — just on only one of the two extension classes.
- Symptom is invisible in singleplayer / single-machine testing; only surfaces with two peers connected.

### Diagnosis pattern
1. Audit `Vermintide-2-Source-Code/scripts/network/unit_extension_templates.lua` to see which extension classes a slot routes through for local vs husk.
2. `Simple*Extension` (e.g. `SimpleInventoryExtension`) handles the locally-owned unit; `SimpleHusk*Extension` (e.g. `SimpleHuskInventoryExtension`) handles remote peers' units. They are **separate root classes with no inheritance** — hooks on one do NOT fire for the other.
3. If the bug surfaces only on one side (local vs husk), check which class is being hooked vs which the bug surfaces on.

### Fix template
Hook both, or hook a function further upstream that both classes route through.

```lua
-- WRONG -- only fires for the local player
mod:hook_safe("SimpleInventoryExtension", "wield", function(self, slot_name)
    _on_wield(self, slot_name)
end)

-- RIGHT (option A) -- hook both
local function _on_wield(self, slot_name) ... end
mod:hook_safe("SimpleInventoryExtension", "wield", _on_wield)
mod:hook_safe("SimpleHuskInventoryExtension", "wield", _on_wield)

-- RIGHT (option B) -- hook a shared upstream entry point if one exists
mod:hook_safe("SomeSharedDispatcher", "common_method", _on_wield)
```

Engine-quirk bullet: `CLAUDE.md § Hooks that silently no-op`.

### Related Issues / commits
- Issue [#35](https://github.com/Ensrick/vermintide-2-tweaker/issues/35) — cosmetics_tweaker `SimpleHuskInventoryExtension.extensions_ready` was the dead hook, but the underlying class doesn't exist in the form referenced (compound bug with § 1b)
- Generic guidance in `CLAUDE.md` lines 305+

---

## 6. Forward-reference closure binds to global instead of file-local

**First seen:** 2026-05-?? (gt latent bug, fixed in v0.2.56-dev)
**Canonical Issue:** [#13](https://github.com/Ensrick/vermintide-2-tweaker/issues/13)
**Lives in:** any closure that assigns to a name whose `local` declaration is below it in the file

### Symptoms
- `mod_lua` file declares `local _foo = false` at line N. A closure compiled at line N-100 assigns `_foo = false`.
- The closure's assignment writes to **`_G._foo`** (global), not the file-local.
- File-local readers further down see the original value forever; the global write is a silent no-op for their purposes.
- Specific gt manifestation: pause/unpause desync after a level transition because `on_game_state_changed` cleared the global `_pause_active` but the pause-toggle code read the file-local `_pause_active` declared later in the file.

### Diagnosis pattern
1. Run `tools/mod-lint/lint-mod.ps1 <mod>` — the lint includes a forward-ref check that flags this pattern.
2. Manual: grep the file for `^local <name>\b` — if the local declaration is below a closure that writes to the same name, the closure binds to `_G.<name>`.
3. Smoking gun at runtime: `/lua print(rawget(_G, "<name>"))` after toggling the feature — if it prints a value (instead of `nil`), the closure is writing to the global.

### Fix template
Add a forward declaration ABOVE the closure, then drop `local` from the original declaration so it reuses the forward-decl slot.

```lua
-- WRONG -- closure at line 632 binds to _G._pause_active
local function on_game_state_changed()
    _pause_active = false  -- binds to global because local is declared later
end
mod:hook(...)
-- ...many lines later...
local _pause_active = false  -- this is the file-local readers use

-- RIGHT -- forward-declare at top of file, drop `local` on the later assignment
local _pause_active   -- forward declaration
local function on_game_state_changed()
    _pause_active = false  -- now binds to the forward-decl file-local
end
mod:hook(...)
-- ...many lines later...
_pause_active = false  -- (no `local`) reuses the forward-decl slot
```

Lint coverage: already in `tools/mod-lint/lint-mod.ps1`.

### Related Issues / commits
- Issue [#13](https://github.com/Ensrick/vermintide-2-tweaker/issues/13) — gt `_pause_active`
- Issue [#1](https://github.com/Ensrick/vermintide-2-tweaker/issues/1) — CWV: 22 bare-global declarations to refactor to forward-decl pattern
- `general_tweaker/CHANGELOG.md` v0.2.56-dev — fix entry with the forward-decl pattern explanation
- `general_tweaker.lua:151-161` — canonical comment block documenting the gotcha

---

## 7. `on_disabled` doesn't unwind global mutations (togglable-mod limitation)

**First seen:** 2026-05-?? (gt v0.2.48-dev audit, accepted as limitation in v0.2.56-dev)
**Canonical Issue:** [#15](https://github.com/Ensrick/vermintide-2-tweaker/issues/15)
**Lives in:** any mod with `is_togglable = true` in its `.mod` file

### Symptoms
- User toggles the mod off via the VMF menu mid-session, expects vanilla behavior, gets mod behavior.
- All runtime mutations into `script_data`, `RagdollSettings`, `BuffTemplates`, `CareerSettings`, `PlayerUnitMovementSettings`, `InventorySettings`, etc. persist after disable.
- Only the camera offset (or whatever the existing `on_disabled` body explicitly restores) gets reverted.

### Diagnosis pattern
1. Check the mod's `.mod` file for `is_togglable = true`.
2. Read the mod's `on_disabled` body. Compare to the set of vanilla tables/fields the mod's `on_enabled` (or its load-time code) mutates.
3. Any field mutated outside `on_disabled`'s restore set will persist after disable.

### Fix template
Two acceptable shapes:

**A) Document the limitation (cheap, what gt v0.2.56 chose):**

```lua
mod.on_disabled = function()
    -- ... existing restores ...
    mod:echo("Disable does not fully unwind active mutations. Restart the game for a clean vanilla state.")
end
```

Plus a bullet in `itemV2.cfg`'s description under a **Compatibility** section so users see it pre-subscribe.

**B) Snapshot + restore (expensive, only worth it for hot mods):**

```lua
local _vanilla_snapshots = {}
local function _snapshot_and_mutate(tbl, key, new_value)
    if _vanilla_snapshots[tbl] == nil then _vanilla_snapshots[tbl] = {} end
    if _vanilla_snapshots[tbl][key] == nil then
        _vanilla_snapshots[tbl][key] = tbl[key]
    end
    tbl[key] = new_value
end
mod.on_disabled = function()
    for tbl, snaps in pairs(_vanilla_snapshots) do
        for key, vanilla in pairs(snaps) do
            tbl[key] = vanilla
        end
    end
    _vanilla_snapshots = {}
end
```

Decision criterion: snapshot/restore is mandatory only if the mod is published as `stable` AND the user-visible mutation surface is small. Otherwise (A) is fine.

### Related Issues / commits
- Issue [#15](https://github.com/Ensrick/vermintide-2-tweaker/issues/15) — gt
- `general_tweaker/CHANGELOG.md` v0.2.56-dev (Issue #15 fix)

---

## 8. Layered `mod.update` rewraps — silent-drop risk

**First seen:** 2026-05-?? (gt audit, fixed in v0.2.56-dev)
**Canonical Issue:** [#16](https://github.com/Ensrick/vermintide-2-tweaker/issues/16)
**Lives in:** any mod with multiple `local _orig = mod.update; mod.update = function(dt) _orig(dt); ... end` chains

### Symptoms
- Five consumers chained via `local _orig = mod.update; mod.update = function(dt) _orig(dt); ... end` (no central registry).
- An accidental edit `mod.update = function(dt) ... end` without preserving `_orig` silently drops EVERY earlier consumer.
- Drop is invisible until the dropped feature stops working.
- No per-consumer error isolation — one consumer's raise kills every later one in the chain.

### Diagnosis pattern
1. Grep the mod for `mod\.update\s*=\s*function` — if there are 2+ hits in the same file, suspect a chain.
2. Read each site. If they use `local _orig = mod.update` to preserve prior chain, they're layered; if not, they overwrite.
3. Check for a `_update_consumers` (or similar) registry — its absence + 2+ rewraps = vulnerable.

### Fix template
Replace the chain with a single dispatcher + a registry of named consumers.

```lua
-- WRONG -- 5 layered rewraps, no isolation, accidental edit drops earlier consumers
local _orig1 = mod.update
mod.update = function(dt) _orig1(dt); _tp_camera_tick(dt) end
local _orig2 = mod.update
mod.update = function(dt) _orig2(dt); _post_spawn_reapply(dt) end
-- ... 3 more layers ...

-- RIGHT -- single dispatcher, named consumers, pcall isolation
local _update_consumers = {}
local function _register_update(name, fn)
    table.insert(_update_consumers, { name = name, fn = fn })
end

mod.update = function(dt)
    for _, c in ipairs(_update_consumers) do
        local ok, err = pcall(c.fn, dt)
        if not ok then
            mod:error("[<mod>:update] consumer '%s' raised: %s", c.name, tostring(err))
        end
    end
end

_register_update("tp_camera",         function(dt) _tp_reapply_timer(dt) end)
_register_update("post_spawn_reapply", function(dt) _post_spawn_reapply(dt) end)
-- ... etc ...
```

### Related Issues / commits
- Issue [#16](https://github.com/Ensrick/vermintide-2-tweaker/issues/16) — gt 5-layer chain
- `general_tweaker/CHANGELOG.md` v0.2.56-dev — registry pattern shipped, 5 sites converted

---

## 9. Host/client RPC schema divergence (silent state corruption)

**First seen:** 2026-05-19 desync investigation prompt; pilot landed 2026-05-25
**Canonical Issue:** [#27](https://github.com/Ensrick/vermintide-2-tweaker/issues/27) (pattern); follow-ups [#42](https://github.com/Ensrick/vermintide-2-tweaker/issues/42)–[#46](https://github.com/Ensrick/vermintide-2-tweaker/issues/46) (per-mod propagation)
**Lives in:** every `mod:network_send` / `mod:network_register` pair in any RPC-bearing mod

### Symptoms
- Two peers running different mod versions; the wire payload shape changed between versions.
- Receiver parses positional args by position, writes wrong field types into local state.
- Mod misbehaves in confusing MP-specific ways with no log trace pointing at the real cause.
- Symptom can manifest 30+ minutes downstream of the actual RPC mismatch.

### Diagnosis pattern
1. Confirm peers are on different versions of the mod (compare each peer's load banner `[<mod>] enabled v<X.Y.Z>`).
2. Compare the mod's `<MOD>_RPC_SCHEMA` constant across the two versions.
3. If schema versions differ AND the mod hasn't shipped the explicit schema-gate pattern (Issue #27) for that RPC, payload corruption is plausible.
4. If schema gate IS shipped, look for `[rpc:schema] <channel> mismatch from peer=<peer>: peer sent v<n>, we expect v<our>. Dropping.` in the receiver's log — that's the clean-drop signal.

### Fix template
Prepend a per-mod schema-version constant as the first positional arg of every `network_send`; gate receivers on it.

```lua
-- Near MOD_VERSION:
-- Bump ONLY when changing RPC payload shape (add/remove/reorder/retype fields).
local CT_RPC_SCHEMA = 1

-- Sender:
mod:network_send("ct_sync_host_settings_chunk", "others",
    CT_RPC_SCHEMA,                  -- FIRST positional arg, always
    session, seq, total, chunk_str) -- existing payload follows

-- Receiver:
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
```

Full mechanic + when-to-bump rules + graceful-degradation behavior: `VMF_RECIPES.md § 10`. Anti-pattern citation: `PROJECT_STANDARDS.md § 9.9a`.

### Related Issues / commits
- Issue [#27](https://github.com/Ensrick/vermintide-2-tweaker/issues/27) — original spec, ct pilot
- Issue [#28](https://github.com/Ensrick/vermintide-2-tweaker/issues/28) — bt net_replay ring buffer (sibling MP hardening)
- Issues [#42](https://github.com/Ensrick/vermintide-2-tweaker/issues/42), [#43](https://github.com/Ensrick/vermintide-2-tweaker/issues/43), [#44](https://github.com/Ensrick/vermintide-2-tweaker/issues/44), [#45](https://github.com/Ensrick/vermintide-2-tweaker/issues/45), [#46](https://github.com/Ensrick/vermintide-2-tweaker/issues/46) — propagation to et, lt, gt, cosmetics, cim
- `chaos_wastes_tweaker/CHANGELOG.md` v0.7.114-dev — pilot bump entry

---

## 10. Stale Workshop bundle vs source (deploy timing)

**First seen:** 2026-05-25 (wt v0.12.78 cfg-title-revert saga during multi-agent session)
**Canonical Issue:** (none filed — covered by multi-agent doctrine in `CLAUDE.md § Multi-agent coordination`)
**Lives in:** the deploy-test loop, not the code

### Symptoms
- Source `.lua` change made + bundle rebuilt + deployed; user sees the OLD version banner in chat ("Weapon Tweaker v0.12.77" when source is at v0.12.78).
- User assumes the fix didn't ship and re-iterates.
- In multi-agent scenarios: another session reverts `MOD_VERSION` while the first session is mid-iteration, masking the real fix.

### Diagnosis pattern
1. Compare three mtimes:
   - Source `.lua`: `(Get-Item <mod>/scripts/mods/<mod>/<mod>.lua).LastWriteTime`
   - Local bundle: `(Get-Item <mod>/bundleV2/*.mod_bundle).LastWriteTime`
   - Workshop folder bundle: `(Get-Item <Steam>/steamapps/workshop/content/552500/<workshop_id>/*.mod_bundle).LastWriteTime`
2. Source newer than local bundle → build didn't run / failed silently. Re-run `VMBLauncher.exe build <mod>`.
3. Local bundle newer than Workshop folder bundle → deploy didn't run. Re-run `VMBLauncher.exe deploy <mod>`.
4. All three in sync but in-game banner shows old version → Steam reverted the folder (rare — most often a transient mid-upload state).
5. Multi-agent scenario: check `.in_progress/<mod>.md` sentinels (`Get-ChildItem .in_progress\*.md -Exclude README.md`); check `MOD_OWNERSHIP.md` status column. Coordinate with the other session before re-deploying.

### Fix template
No code change — this is process. Three doctrines:

1. **Always increment `MOD_VERSION` before every build** so the in-game banner confirms the new build deployed. (`CLAUDE.md § Version bumping`.)
2. **Use `VMBLauncher.exe all <mod>`** instead of ad-hoc pipelines — it handles hash verification, BOM, and the PC-B remote push in one go. (`tools/vmb-launcher/CLAUDE.md`.)
3. **Drop a `.in_progress/<mod>.md` sentinel** when starting substantive multi-step work; check the directory before editing a mod another session might own. (`CLAUDE.md § Multi-agent coordination`.)

### Related Issues / commits
- `CLAUDE.md § Multi-agent coordination` — the canonical doctrine that grew out of the 2026-05-25 wt revert saga
- `weapon_tweaker/CHANGELOG.md` v0.12.77 → v0.12.79 — the actual saga (multi-return bug exposed against a moving MOD_VERSION target)

---

## 11. Lua 5.1 200-locals-per-function limit

**First seen:** generic Stingray compile error
**Canonical Issue:** (none — engine quirk, doctrine-only)
**Lives in:** any single function (including the top-level chunk) accumulating > 200 `local` declarations

### Symptoms
- Stingray compile error at build time: `main function has more than 200 local variables`.
- The cited line is the 201st local declared, NOT the problem source — the problem is the cumulative count.

### Diagnosis pattern
1. Count `local` declarations in the cited function (or top-level chunk if no enclosing function).
2. If > 200, wrap helper groups in `do ... end` blocks so their locals release back to the main chunk.

### Fix template
See `CLAUDE.md § High-frequency engine quirks` (line 296) — `do ... end` block wrapping is the canonical workaround. No copy-paste fix snippet is necessary; the doctrine is "scope helper locals into a `do` block."

### Related Issues / commits
- `CLAUDE.md § High-frequency engine quirks` — short-form doctrine
- `DEVELOPMENT.md § Stingray / Lua engine quirks` — full mechanic

---

## 12. Quaternion / Vector3 stack-temporary lifetime

**First seen:** generic Stingray engine quirk
**Canonical Issue:** (none — engine quirk, doctrine-only)
**Lives in:** any storage of a raw `Quaternion` / `Vector3` / `Matrix4x4` past the current frame

### Symptoms
- A stored rotation / position silently corrupts on the next frame.
- Symptoms can be wild: weapon hand floating, scale jittering, NaN positions, "the value was right when I logged it but wrong when I applied it."

### Diagnosis pattern
1. Find any global / table / upvalue holding a raw `Quaternion.identity()` / `Quaternion(x,y,z,w)` / `Vector3(...)` / `Matrix4x4(...)` return.
2. If the storage outlives the current frame (assigned in one hook, read in another) — bug.

### Fix template
See `CLAUDE.md § High-frequency engine quirks` (line 295) — use `QuaternionBox` / `Vector3Box` / `Matrix4x4Box` for any storage that outlives a single statement; call `:unbox()` at apply time for a fresh raw value. No additional snippet needed; the doctrine is "Box-wrap anything you store."

### Related Issues / commits
- `CLAUDE.md § High-frequency engine quirks` — short-form doctrine
- `DEVELOPMENT.md § Stingray / Lua engine quirks` — full mechanic

---

## 13. Cross-character state machine collision (cosmetic-side suspicion, root cause elsewhere)

**First seen:** 2026-05-25 (apparent symptom of the wt v0.12.77 multi-return bug)
**Canonical Issue:** (none — covered by adjacent classes)
**Lives in:** cross-character weapon equip scenarios (cwv / wt slot swaps where two melee state machines could co-exist on the same 1P rig)

### Symptoms
- Weird-looking 1P weapon grip on a character with a cross-character variant equipped (e.g. Grail Knight with bastard_sword in `slot_melee` + sword_shield_breton in `slot_ranged` via cwv cross-slot routing).
- Symptom can LOOK like two state machines fighting for the same 1P rig.

### Diagnosis pattern
1. **First** check the bug isn't actually § 3 (nil-hole unpack) corrupting the 1P weapon unit on its way through `GearUtils.spawn_inventory_unit` — that's what the v0.12.77 burn turned out to be.
2. If § 3 is ruled out, audit the slot extension scoping in `weapon_tweaker`'s cross-slot routing — confirm the variant's extension is scoped to one slot and doesn't try to install on both.

### Fix template
Largely a "diagnose narrowly before assuming" entry. The recurring lesson: the apparent symptom (visual grip weirdness on a cross-character variant) is a **bad hypothesis to chase first** — the root cause is more often a generic multi-return / nil-hole / hook-drop bug masquerading as a state-machine collision. Walk § 1, § 2, § 3, § 4, § 5 before assuming this class.

### Related Issues / commits
- `weapon_tweaker/CHANGELOG.md` v0.12.79 — the saga where this hypothesis was burned before the real cause (§ 3) was identified
- `character_weapon_variants/J_LEFTWEAPONATTACH_INVESTIGATION.md` — 20-version dual-wield rig saga (adjacent class, well-documented)

---

## 14. Cross-mod chat-command name collision

**First seen:** 2026-05-23 (`regression_test` collision across 7 mods)
**Canonical Issue:** [#11](https://github.com/Ensrick/vermintide-2-tweaker/issues/11)
**Lives in:** every `mod:command("<name>", ...)` registration

### Symptoms
- Console log: `[MOD][<mod>][ERROR] (command): command name '<name>' is already used by another mod '<other_mod>'`.
- Only the first mod to register the name wins; later registrations silently no-op (except for the visible ERROR line, which can be missed on later registrations that detected the collision and didn't retry).
- A `/regression_test` invocation runs only ONE mod's test, not all 7's.

### Diagnosis pattern
1. Grep console_log for `command name '<name>' is already used`.
2. Run `qa/check_command_collisions.ps1` (wired into `qa/run_all.ps1`) — flags any chat-command name registered by 2+ mods.

### Fix template
Prefix every chat command with the mod's short-id.

```lua
-- WRONG -- collides with every other mod that registered the same name
mod:command("regression_test", "Run regression tests", function() ... end)

-- RIGHT -- short-id prefixed namespace
mod:command("wt_regression_test", "Run weapon_tweaker regression tests", function() ... end)
```

Per-mod inventory: `COMMANDS.md`. Lint coverage: `qa/check_command_collisions.ps1`.

### Related Issues / commits
- Issue [#11](https://github.com/Ensrick/vermintide-2-tweaker/issues/11) — `regression_test` collision across 7 mods
- All 7 mods bumped to add the `<short_id>_` prefix on 2026-05-23

---

## 15. AI Takeover / general RPC silent drop (`"server"` recipient + `_vmf_users` churn)

**First seen:** 2026-05-24 (gt v0.2.49-dev / v0.2.50-dev)
**Canonical Issue:** (none — covered in `VMF_RECIPES.md § 3` and § 3a)
**Lives in:** any `mod:network_send(channel, "server", ...)` call

### Symptoms
- Client-side feature triggers an RPC; host never receives it.
- No error, no warning — the send is silently dropped.
- gt-specific manifestation: client toggles AI Takeover; host's character doesn't switch to AI.

### Diagnosis pattern
1. Grep the mod for `network_send.*"server"` — VMF silently drops `"server"` as a recipient string.
2. If the bug surfaces when host bots churn (lobby reshuffle, bot taking over for a leaver) — suspect `_vmf_users` is stale; see § 3a in VMF_RECIPES.

### Fix template
Replace `"server"` with the resolved host peer_id via `Managers.account:peer_id_of_host()` or equivalent.

```lua
-- WRONG -- "server" is silently dropped
mod:network_send("gt_ai_takeover", "server", peer_id, slot)

-- RIGHT -- resolve the host peer_id and target it explicitly
local host_peer = Managers.account:peer_id_of_host()
if host_peer then
    mod:network_send("gt_ai_takeover", host_peer, peer_id, slot)
end
```

Full mechanic: `VMF_RECIPES.md § 3` (recipients) and § 3a (`_vmf_users` churn).

### Related Issues / commits
- `general_tweaker/CHANGELOG.md` v0.2.49-dev — initial fix (resolve host peer_id)
- `general_tweaker/CHANGELOG.md` v0.2.50-dev — discovery that `_vmf_users` also drops bots; added VMF `ping_vmf_users` workaround

---

## 16. Unescaped `%` in localization string (red error tooltip on hover)

**First seen:** 2026-05-25 (`verminious_dreams_lighting` Debug Logging tooltip — user reported "invalid string format on mouseover")
**Canonical Issue:** (open during fix sweep — search GH issues for `localization_format_safe`)
**Lives in:** any `*_localization.lua` value containing a literal `%` (env var like `%APPDATA%`, percentage like `5%`, etc.)

### Symptoms
- User hovers a setting in the VMF mod options panel; the tooltip renders as a red error string ("invalid option '%A' to 'format'" or similar).
- Affects only the hover path — the panel itself opens fine, the offending widget's title renders fine. ONLY the tooltip is corrupt.
- Console log shows a `safe_string_format` warning naming the loc key.
- Most common offender: tooltips that reference a Windows env var by name (`%APPDATA%`, `%USERNAME%`, `%TEMP%`). Second most common: percentage descriptions (`+15%`, `5% chance`, `10%/stack`).

### Diagnosis pattern
1. Run `pwsh -NoProfile -File qa/check_localization.ps1` from the repo root. Exit code 2 + the offending file/key in the ERRORS list.
2. Open the named loc file at the named key; look for a single `%` not followed by another `%` or a format directive.
3. The bug is per-tooltip — only the specific keys flagged need a fix.

### Fix template
Double every literal `%` to `%%`. VMF runs `mod:localize(key)` through `string.format`, which reads `%X` as the format directive `X`.

```lua
-- WRONG -- VMF tooltip render path raises "invalid option '%A' to 'format'"
enable_debug_logging_tooltip = { en = "Logs to %APPDATA%\\Fatshark\\Vermintide 2\\console_logs\\." },

-- WRONG -- same bug, percentage form
trait_swift_slaying_description = { en = "+20% attack speed for 5s on crit." },

-- RIGHT
enable_debug_logging_tooltip = { en = "Logs to %%APPDATA%%\\Fatshark\\Vermintide 2\\console_logs\\." },
trait_swift_slaying_description = { en = "+20%% attack speed for 5s on crit." },
```

After fix, re-run `qa/check_localization.ps1` and confirm exit 0/1 (no ERRORS). Then run `/<mod>_regression_test` in-game to confirm the new `localization_format_safe` runtime check passes.

### Related Issues / commits
- 2026-05-25 monorepo-wide sweep — all 16 active mods had `enable_debug_logging_tooltip` shipped with literal `%APPDATA%`. Fixed by escaping to `%%APPDATA%%` per `LOCALIZATION_STANDARD.md` § 1 "Recurring offender".
- Prior burn — `weapon_tweaker` Fix 1 (v0.12.63-dev), `lobby_tweaker` Fix 1 (v0.1.1-dev): percentage escaping. Documented in `AUDIT_section_c.md` P0.

### Why this is a repeat offender
The pre-commit hook's `qa/check_localization.ps1` catches it at COMMIT time — but agent workflows that build/deploy without committing slip past. Multi-layer defense (added 2026-05-25):

1. **Static check** — `qa/check_localization.ps1` (pre-commit hook).
2. **Build doctrine** — `tools/vmb-launcher/CLAUDE.md` § "Run check_localization.ps1 before declaring any localization edit complete".
3. **Runtime test** — `_rt_register("localization_format_safe", ...)` in every mod (run via `/<mod>_regression_test`).
4. **PROJECT_STANDARDS.md § 3.6** — canonical Debug Logging tooltip text now uses `%%APPDATA%%` so pattern-copy can't reintroduce the bug.

---

## 17. Chat-echo spam (load-time banners, on_setting_changed leaks)

**First seen:** 2026-05-25 (user feedback: "needless echos to the chat when enabling debug logging" + "CWV echoing on startup before debug logging is even on")
**Canonical Issue:** (none — codified in `PROJECT_STANDARDS.md § 3.6 "Chat-echo policy"` and this entry; no GH issue filed because the fix is the new doctrine + a one-pass sweep)
**Lives in:** any `mod:echo(...)` call at module load, in `mod.on_setting_changed`, or inside `mod.on_enabled` / `mod.on_disabled` for non-operational confirmations

### Symptoms
- User loads into the keep; chat fills with 13+ `<Mod Name> v<X.Y.Z>` banner lines from the load-time `mod:echo` in every installed Tweaker mod.
- User flips ANY widget in the VMF menu (including the universal `enable_debug_logging` Debug Logging checkbox); chat echoes `"Setting changed: enable_debug_logging"` or similar from a stray `mod.on_setting_changed` echo.
- Effect is inconsistent across mods (some mods have it, some don't, some gate it on debug toggle — the inconsistency is the user-visible bug).
- No functional impact — purely chat clutter that obscures actually-actionable messages from in-mission events.

### Diagnosis pattern
1. Grep the mod's main lua for `mod:echo(.*MOD_VERSION` — any hit at module top-level is the load-time banner.
2. Grep for `mod\.on_setting_changed\s*=` then read the function body — any `mod:echo` inside that's not gated on a specific high-impact setting_id is the leak.
3. Grep for `mod\.on_enabled\s*=` / `mod\.on_disabled\s*=` — version-banner echoes there are also load-spam.
4. Cross-reference against `PROJECT_STANDARDS.md § 3.6 "Chat-echo policy"` decision matrix — if the call site is in the "NEVER" row, delete it.

### Fix template
Delete (or downgrade) per the matrix. The applied marker `mod:info("[<mod>] enabled v%s settings_fp=%s", ...)` line already covers version visibility in the log.

```lua
-- WRONG -- module-load banner spam
mod:info("Career Tweaker v%s loaded", MOD_VERSION)
mod:echo("Career Tweaker v" .. MOD_VERSION)

-- RIGHT -- log-only, applied marker further down handles chat-side
mod:info("Career Tweaker v%s loaded", MOD_VERSION)

-- WRONG -- echoes on EVERY widget flip, including Debug Logging itself
mod.on_setting_changed = function(setting_id)
    mod:echo("Setting changed: " .. tostring(setting_id))
    -- ...rest...
end

-- RIGHT -- log-only via _dbg (gated on enable_debug_logging)
mod.on_setting_changed = function(setting_id)
    _dbg("on_setting_changed: %s", tostring(setting_id))
    -- ...rest...
end
```

### Keep-criteria (do NOT remove)
- Echoes inside `mod:command(...)` bodies — user invoked the command via chat.
- Echoes in `mod.on_setting_changed` for explicit high-impact toggles (`bt`'s master, `gt`'s AI takeover).
- Echoes in `mod.on_disabled` documenting limitations the user must know about (`gt`'s "Disable does not fully unwind active mutations" — Issue #15 canonical pattern).
- Echoes in hook bodies giving user-operational feedback when something they triggered actually happened (e.g. `ct`'s "Granted N starting boon(s)" — the user is responsible for the toggle that caused it).

### Variant B: `mod:warning` believed log-only, actually posts to CHAT (Issue #240)

**First seen:** 2026-07-02 (et v0.7.24-dev — "Enemy Tweaker keeps spitting out awful messages in the chat log")

A mod routes "log-only" diagnostics through `mod:warning` on the assumption the warning channel is file-only. It is not: upstream VMF `logging.lua` `load_logging_settings()` defaults `warning` to mode 3, and `send_to_chat = mode >= 2` — so `mod:warning` (and `mod:error` / `mod:echo`, both also mode 3) posts to chat AND log unless the user picks a custom VMF logging mode. Only `info` (mode 1) and `debug` (mode 0) are chat-silent by default. Corollary: a helper that pairs `mod:warning` + `mod:echo` for "log + chat" posts to chat TWICE.

**Symptom:** routine `[<mod>:...]` WARNING lines (plateau notices, expected boot-timing states, per-spawn consequences of the user's own sliders) appear in chat every mission load. et v0.7.24-dev log evidence: `console-2026-07-02-21.44.42-8d5b6420-*.log` lines 2335, 4725, 4742, 11124, 11143, 11683.

**Diagnosis:** grep the mod for `mod:warning` and classify each site: routine/expected condition = misrouted; genuine anomaly = acceptable (chat visibility is arguably desirable there).

**Fix template (et v0.7.25-dev, Issue #240):** route log-only alert helpers through pcall-guarded raw engine `printf` (keeps grep-stable prefixes, survives mod-logging-OFF sessions); keep direct `mod:warning` only on genuine failure paths; guard with an `_rt_register` marker check (`et_alert_helpers_log_only_240`).

**Watch list:** `ct_dev` is the § 3.6 reference implementation with the same `_dbg_alert -> mod:warning` routing — same chat spam when its alerts fire. Fold into #169's VMF-native logging sweep.

### Related Issues / commits
- 2026-05-25 monorepo-wide sweep — 14 mods bumped to remove load-time banner echoes + downgrade `mod:echo("Enemy Tweaker: settings updated")` (et) + delete `mod:echo("Setting changed: ...")` (crt). PROJECT_STANDARDS.md § 3.6 "Chat-echo policy" subsection added with the decision matrix.
- See per-mod CHANGELOG entries dated 2026-05-25 titled "Remove startup banner echo + tidy on_setting_changed".
- Issue #240 (2026-07-02) — et alert helpers rerouted to log-only printf (Variant B above).

---

## 18. Invalid VMF widget type breaks options init

**First seen:** 2026-05-25 (general_tweaker v0.2.60-dev — widget #103 `type = "text_input"`)
**Canonical Issue:** (none yet — fix shipped inline + this catalog entry + `qa/check_vmf_widget_types.ps1` static check)
**Lives in:** any `<mod>/scripts/mods/<mod>/<mod>_data.lua` widget definition with `type = "<X>"` where `<X>` is outside the VMF whitelist

### Symptoms
- Chat (or VMF console) error at mod load: `[MOD][<mod>][ERROR] [VMF Mod Manager] (new_mod) mod options initialization: could not initialize mod's options.` — often with a widget index ("Widget N ...").
- The mod's **entire** VMF options page disappears from the in-game mods menu — not just the offending widget.
- The mod itself still loads and runs; runtime `mod:get(setting_id)` reads still work (vanilla settings store survives), but the user has no UI to change settings.
- No game crash, no further error log — silent UI death.

### Diagnosis pattern
1. Run `qa/check_vmf_widget_types.ps1` — exit 2 names the file:line and the invalid type per offending widget.
2. OR grep the chat / mod log for `could not initialize mod's options` — VMF prints the widget index alongside the error.
3. Cross-check the offending widget's `type =` value against the canonical VMF whitelist: **`group` / `header` / `checkbox` / `dropdown` / `numeric` / `keybind`**. Anything else fails validation.
4. Common false-friend types pulled from other frameworks (NOT valid in VMF): `text_input`, `string` (DMF has `description` / DMF/some-others have free-text), `slider` / `percent_slider` / `value_slider` (DMF; VMF uses `numeric` with `range`), `radio`, `multiselect`, `mod_toggle`.

### Fix template
Pick a valid type. For settings that genuinely have no matching VMF widget (e.g. free-text input — there is no VMF `text_input`), drive the setting via a chat command and store via `mod:set(setting_id, value)` instead of registering a widget:

```lua
-- WRONG -- VMF has no "text_input" type; this kills options init
{
    setting_id    = "gt_lobby_motd_text",
    type          = "text_input",   -- invalid
    default_value = "",
},

-- RIGHT (canonical type) -- pick from group/header/checkbox/dropdown/numeric/keybind
{
    setting_id    = "gt_lobby_motd_enabled",
    type          = "checkbox",
    default_value = false,
},

-- RIGHT (no widget) -- store via chat command, no UI entry
-- _data.lua: leave a comment explaining the absence
-- A widget here with type="text_input" caused widget#103 to fail VMF
-- validation (no such VMF type) and broke gt options init entirely.
-- Drive the setting via /gt_lobby_motd_set <text> instead.
--
-- <mod>.lua:
mod:command("gt_lobby_motd_set", "Set MOTD text", function(...)
    local text = table.concat({ ... }, " ")
    mod:set("gt_lobby_motd_text", text)
    mod:echo("MOTD set to: " .. text)
end)
```

Full canonical whitelist + per-type usage examples: `VMF_RECIPES.md § 6a` ("VMF widget type whitelist"). Static check: `qa/check_vmf_widget_types.ps1` (runs in `-Quick` mode + pre-commit hook).

### Related Issues / commits
- general_tweaker v0.2.60-dev (2026-05-25) — widget #103 `type = "text_input"` for `gt_lobby_motd_text` broke gt options init; fix: deleted the widget + added comment + drive via `/gt_lobby_motd_set` chat command.
- `qa/check_vmf_widget_types.ps1` + fixtures (`qa/_test_fixtures/widget_type_bad.lua` + `widget_type_good.lua`) — static check that catches this class going forward.

---

## 19. Hooked vanilla networked fn drops a trailing sync param → RPC re-broadcast loop

**First seen:** 2026-06-19 (weapon_tweaker v0.12.128 → v0.12.132)
**Canonical citation:** wt CHANGELOG v0.12.132-dev; memory `reference_vmf_hook_drops_skip_sync_rpc_loop`
**Lives in:** any `mod:hook(C, m, ...)` where vanilla `C.m` has a trailing networking/control param (`skip_sync`, `is_server`, `do_sync`, `from_local`, …) AND broadcasts an RPC

### Symptoms
- In a 2+ human network game ONLY (solo immune): every human player's husk (3P body) stuck on an endless-repeat / frozen animation; "everyone", every weapon, in the keep/lobby.
- A/B: disabling the hooking mod clears it instantly.
- No error, no crash, no log line — pure runtime network feedback.

### Diagnosis pattern
1. A/B-confirm the mod (disable → gone). Don't trust per-mod static review alone — two workflows here wrongly chased husk-attachment mods that were DISABLED before the A/B pinned it.
2. Grep the mod for `mod:hook("<NetworkedClass>"` and read the hook's parameter list.
3. Grep the decompiled vanilla `function <Class>.<method>` signature; count params. If the hook names FEWER than vanilla declares, the missing trailing param(s) collapse to `nil` when the hook calls `func(...)`.
4. If vanilla does `if not skip_sync and Managers.state.network:game() then …send_rpc…` and the RPC receiver replays with that param = `true`, dropping it makes the receiver re-broadcast → loop.

### Fix template
```lua
-- WRONG -- drops vanilla's 6th param skip_sync; husk replays re-broadcast → loop
mod:hook("AnimationSystem", "anim_event_with_variable_float", function(func, self, unit, event_name, variable_name, variable_value)
    return func(self, unit, event_name, variable_name, variable_value)
end)

-- RIGHT -- thread EVERY vanilla param through (here: skip_sync), or capture ... and splat
mod:hook("AnimationSystem", "anim_event_with_variable_float", function(func, self, unit, event_name, variable_name, variable_value, skip_sync)
    return func(self, unit, event_name, variable_name, variable_value, skip_sync)
end)
```

Distinct from the multi-RETURN collapse gotcha (`VMF_RECIPES.md § 2`, return values) and from #15 (`"server"` recipient drop) — this is a dropped ARGUMENT silently flipping network re-send. Vanilla refs: `scripts/entity_system/systems/animation/animation_system.lua:139` (signature), `:140` (re-send gate), `:312` (receiver passes `skip_sync=true`).

---

## Format anti-patterns (for future entries)

When adding a new bug class entry, hold the line on:

- **Bullet points + code blocks only.** No narrative paragraphs.
- **Cite by file:section.** Don't duplicate full doc content into the entry; cross-reference `VMF_RECIPES.md § N` / `CLAUDE.md § <heading>` / etc.
- **Document actual burns only.** Don't invent classes that haven't been seen — every entry above has at least one shipped fix to cite.
- **Always include the canonical Issue / CHANGELOG / commit citation.** No entry without a paper trail.
- **Don't bump mod versions when adding a new entry here.** Docs-only changes don't deploy.

---

## 20. Input-device re-route under an open menu (soft-lock, "game frozen")

**First seen:** 2026-07-05 (gut_dev v0.2.189-dev Free Camera #307, fixed v0.2.192-dev)
**Canonical Issue:** [#307](https://github.com/Ensrick/vermintide-2-tweaker/issues/307)
**Lives in:** any feature that grabs exclusive input (`block_device_except_service`, free-flight entry, custom input services) while a menu/view can be open

### Symptoms
- User reports the game "froze" after toggling a mod option FROM the options menu; no input works (no clicks, no ESC, no chat); they force-close via Steam.
- The console log shows NO crash: activity stops at the toggle timestamp, then a CLEAN exit ("Lua signals application exit" + save) when Steam sends the close request. A real engine freeze or crash never writes those exit lines.

### Diagnosis pattern
1. Log tail shows orderly shutdown -> it is an input soft-lock, not a hang/crash.
2. Find the last user action before the gap (VMF widget probes / setting toggles in the log).
3. Grep the feature for `block_device_except_service` / input-service acquisition running at setting-changed time with no check for an open view.

### Fix template
Gate the input grab on "no menu/view open": `local iui = Managers.ui._ingame_ui; iui.menu_active or iui.current_view ~= nil` (ingame_ui.lua:228/:765; instance via ui_manager.lua:26). DEFER the activation to `mod.update` on the first frame the menu is closed rather than refusing (the options checkbox is the primary entry point). Make every activation path announce the exit key via `mod:echo`; a raw `Keyboard.button` poll is the only reliable exit while devices are re-routed. Clear the pending flag on `on_game_state_changed`.

### Reference fix
`gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_freecam.lua` (commit 84f49bb): `_menu_open()` gate + `_pending_menu_close` deferral + apply()-owned feedback.

---

## 21. POSITION_LOOKUP dead Vector3 for the local player in mod code (works-but-reports-failed / per-frame error spam)

**First seen:** 2026-07-05 (gt_dev v0.2.187, /recall_position_N; second instance same day in _gt_debug_highlights)
**Canonical Issue:** [#337](https://github.com/Ensrick/vermintide-2-tweaker/issues/337)
**Lives in:** ANY mod code path (chat command OR mod.update) that reads `POSITION_LOOKUP[<local player unit>]` directly, or calls a vanilla function that reads it internally

### Symptoms
- `bad argument #N to '__index'` / `(Vector3 expected, got userdata)` naming a line that reads `POSITION_LOOKUP[...]`, even though the unit is alive.
- Partial success: everything the vanilla function did BEFORE the lookup read landed (e.g. `teleport_to` moves the player, then dies on its last line, `set_falling_height`), so the feature "works" while the mod's pcall reports failure - and the steps AFTER the raise are silently skipped (`set_ignore_next_fall_damage` in the teleport case).
- Or per-frame error spam from a mod.update consumer that reads the lookup directly (1182x in one session for the debug-highlights draw - which also meant the feature silently rendered nothing).
- Freshly created `Vector3(...)` values in the same callback work fine; only the STORED lookup entry is dead.

### Diagnosis pattern
1. The error names a line; check whether it reads `POSITION_LOOKUP[...]` (or another per-frame temporary cache).
2. Is the unit the LOCAL PLAYER? AI/pickup entries are re-seeded every frame by their own systems (aggro/ai_slot/spawner), but no Lua-reachable phase refreshes the local player's entry for mod code: `mod.update` and chat commands BOTH fire from `Managers.mod:update(dt)` at the TOP of the frame (boot.lua:749; vmf_loader.lua:52-54), before `StateIngame.pre_update`'s `UPDATE_POSITION_LOOKUP()` (state_ingame.lua:808). The entry a mod sees is a dead frame-pool handle - DEFERRING TO mod.update DOES NOT HELP (learned the hard way: the v0.2.188 deferral fix did not fix it).
3. Vanilla never trips this because every vanilla caller runs inside the entity-update phase after the refresh (e.g. all `teleport_to` callers are BT bot actions, bt_bot_teleport_to_ally_action.lua:84).
4. Related but distinct: class "AI-takeover despawn 1-frame nil deref" (`memory: reference_vt2_ai_takeover_despawn_poslookup_crash`) - there the entry is NIL after despawn; here the entry EXISTS but is a dead pool handle.

### Fix template
Two rules, by direction of access:

```lua
-- READING a position in mod code: NEVER via POSITION_LOOKUP for the local player.
-- WRONG (dead handle, per-frame spam):
local player_pos = POSITION_LOOKUP[player_unit]
-- RIGHT (live read, valid for the whole synchronous call):
local player_pos = Unit.world_position(player_unit, 0)

-- CALLING a vanilla function that reads the lookup internally (teleport_to ->
-- set_falling_height): seed a LIVE destination Vector3 into the entry first.
local PL = rawget(_G, "POSITION_LOOKUP")
if PL then PL[unit] = Vector3(x, y, z) end   -- harmless one-frame poke; engine
loco:teleport_to(Vector3(x, y, z), rot)      -- bulk refresh rewrites it next frame
```

Queue/defer only for its OWN value (re-validation, last-write-wins on mashed commands) - it does not change the lookup's validity.

### Reference fix
`general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_saved_positions.lua` + `_gt_debug_highlights.lua` (gt_dev v0.2.189-dev, commit 7442d80): live seed before `teleport_to`; live `Unit.world_position` read in the overlay draw. The v0.2.188 defer-only attempt (e69ca76) is the documented dead end.

## 22. ShadingEnvironment.blend native AV: undefined VARIATION vs non-resident RESOURCE (mission-substituted UI worlds)

**First seen:** 2026-06-24 (cim_dev in-mission Athanor, keep-gated at v0.8.23); root-caused 2026-07-02/03 (cosmetics_tweaker 0.9.62..0.9.66-dev)
**Canonical Issues:** [#228](https://github.com/Ensrick/vermintide-2-tweaker/issues/228), [#235](https://github.com/Ensrick/vermintide-2-tweaker/issues/235); applied to cim in [#83](https://github.com/Ensrick/vermintide-2-tweaker/issues/83) (v0.8.48-dev)
**Lives in:** any mod that opens a keep-authored view mid-mission and substitutes its viewport world's `shading_environment` (cim forge/customization, gut mission inventory, cosmetics preview)

### Symptoms
Two DISTINCT failure modes that look alike in reports - distinguish them first:
- **Non-resident env RESOURCE** -> clean engine fatal at world create: `Resource not loaded, type: ... ('shading_environment'), name: ...`. Happens at mount time.
- **Undefined env VARIATION** -> native ACCESS VIOLATION (0xc0000005), main thread, Lua stack `[0] =[C] blend / [1] script_world.lua render / [2] world_manager.lua render`. Happens on a RENDERED frame (often ~1s after content load), and no pcall can catch it. The env resource IS resident - only the requested variation name is absent.

### Diagnosis pattern
1. `ScriptWorld.render` blends `World.get_data(world, "shading_settings")` every frame (script_world.lua:122; runtime line numbers shift - #228 logs said :176). `shading_settings[1]` starts as `"default"` (world_manager.lua:44), which EVERY env defines - safe.
2. Find the variation writer. On the customization surface it is `HeroWindowItemCustomization._present_item -> _update_environment` writing `item_preview_environment or "weapons_default_01"` (hero_window_item_customization.lua:1377-1381 / :583-594). The weave-forge windows write NO variations (grep-verified; their only ShadingEnvironment call is the set_fullscreen_effect blur set_scalar).
3. `weapons_default_01` etc. are variations of `environment/ui_store_preview` (keep witnesses: store_window_item_preview.lua:88+1367, hero_window_gotwf_item_preview.lua:67+607). `environment/ui_hdr` does NOT define them -> AV when a mission-substituted ui_hdr world receives that request.
4. Bonus finding (#235 instrumentation, host log 2026-07-03): `environment/ui_store_preview` IS resident mid-mission (`Application.can_get("shading_environment", ...)` = true), while `ui_hdr` is a 2D tonemapping env with zero 3D radiance (16x exposure boost stayed pure black).

### Fix template
```lua
-- 1. Pick the substitute env by RESIDENCY at use time, preferring the lit env
--    that DEFINES the variations; environment/blank (boot_assets, engine
--    default) is the never-fails fallback.
local candidates = { "environment/ui_store_preview", "environment/ui_hdr" }
-- pcall'd Application.can_get("shading_environment", name); fall back to "environment/blank"

-- 2. Pin the blend variation on the writer: allow vanilla's request only when
--    the world's env defines it, else force_default=true (blend asks only for
--    "default").
mod:hook("HeroWindowItemCustomization", "_update_environment", function(func, self, env, force_default)
    if in_keep then return func(self, env, force_default) end
    if world_env_defines_variation then return func(self, env, force_default) end
    return func(self, env, true)
end)
```
Multiple mods hooking the same writer chain safely: `force_default=true` is sticky in the safe direction.

### Reference fix
cosmetics_tweaker v0.9.66-dev (`_create_preview_widget` re-point + `_update_environment` pin, cosmetics_tweaker.lua ~2619-2751); cim_dev v0.8.48-dev (`mod._cim_pick_mission_env` + variation pin, commit 2a4c2c7). Memory: `reference_vt2_shading_env_variation_blend_av`.

---

## 23. Keep-only Gui material drawn mid-mission ("Material 'X' not found in Gui" draw fatal)

**First seen:** 2026-07-02 (gut_dev pose-cosmetics atlas, issue 155); repeats: store atlas (issue 363, gut_dev v0.2.202-dev), area-selection videos (issue 336, gut_dev v0.2.206-dev)
**Canonical Issue:** [#336](https://github.com/Ensrick/vermintide-2-tweaker/issues/336) (area videos; carries the class's fullest two-layer fix)
**Lives in:** any mod-forced keep view/window opened mid-mission (mission map, in-mission inventory/crafting, hero select) whose widgets reference materials vanilla registers only in the keep

### Symptoms
- `<<Lua Error>> scripts/ui/ui_renderer.lua:<line>: Material '<name>' not found in Gui.` at draw time (`Gui.video` shipped `:1345` / decompiled `:1296` for video passes, `ui_passes.lua:194` for texture passes) -> hard CTD. Not catchable at the draw site.
- Works flawlessly in the keep; crashes only when the same screen is opened mid-mission, often seconds after open (the first frame the offending widget actually draws, e.g. hovering an area on mission select).

### Diagnosis pattern
1. Grep the material name against `scripts/ui/views/ingame_ui_settings.lua` - the ingame `ui_renderer_function` / `ui_top_renderer_function` append whole material groups only inside `if is_in_inn then` (`:594-601` AreaSettings videos in ui_renderer_function, `:681-688` in ui_top_renderer_function; the same blocks add achievement atlas, inn singles, lock test, pose cosmetics, tutorial videos, DLC `ui_materials_in_inn`).
2. If not there, grep DLC `*_ui_settings.lua` for `ui_materials_in_inn` (e.g. `store_ui_settings.lua:85`).
3. Find the draw site (widget texture pass or `UIRenderer.draw_video`) and audit whether the widget can be skipped cleanly - every vanilla consumer of the widget field must nil-guard.
4. Inventory every producer feeding the draw loop, not only
   `create_ui_elements`. Scrollbar `list_widgets` and other local arrays may be
   replaced after the static UI build. Issue #83's
   `icon_block_arch_masked` widget was created by `_setup_weapon_stats` two
   seconds before the fatal and never existed in the arrays covered by the
   earlier static prune.

### Fix template
Two layers, both idempotent (reference `_gut_gui_material_guard.lua`):
```lua
-- 1. INJECT-WHEN-RESIDENT: ONE consolidated UIRenderer.create hook per mod;
--    append "material", <path> pairs for ingame ui/ui_top renderers, gated on
--    pcall'd Application.can_get residency with a self-test (can_get on a
--    known-resident material must return true, else treat can_get as
--    untrustworthy and skip). printf the injected/skipped outcome.
-- 2. SKIP-THE-WIDGET: where injection can self-skip (resource not resident in
--    this mission), guard the widget CREATION site so the material is never
--    drawn (e.g. no-op _assign_video_player when the material is not in the
--    Gui; the static fallback image stays). Verify every vanilla consumer
--    nil-guards the widget before relying on the skip.
```
Layer 1 alone is not a fix (residency varies per mission - the pose atlas usually self-skips); layer 2 alone loses content the renderer could legally show (the store atlas IS resident and injects fine). Ship both.

For dynamic list factories, put the guard immediately after the producer and
prove each texture-bearing pass against the exact renderer that consumes that
list. Disable only an unsafe pass; preserve its text/hotspot/safe-texture
siblings. `UIWidget.init` clones content/style but retains the pass array, so
mutation must clone-on-write or it can suppress sibling instances and later
Keep widgets that share the definition. A broad `_draw`/`UIRenderer` `pcall` is
too late and too wide.

### Reference fix
gut_dev `_gut_gui_material_guard.lua` (pose atlas + store atlas + area videos in the one consolidated `UIRenderer.create` hook) + `_gut_mission_map.lua` video-widget skip guards, commit 1b2cea8 (v0.2.206-dev). CIM `_cim_forge_widget_material_policy.lua` + `_setup_weapon_stats` producer hook (issue #83, v0.8.92-dev) is the dynamic-list reference. Related but distinct: class 22 (shading-env VARIATION AV - env resident, variation name absent); `memory: reference_vt2_create_screen_gui_missing_material_crash` (create_screen_gui C-fatal at Gui CREATE time, pre-filter the material list).

## 24. PlayerManager.remove_player fires on LEVEL TRANSITIONS, not just disconnects (peer-keyed caches wiped every map change)

**Symptom.** Any per-peer runtime store purged from a `remove_player` hook silently empties on every keep<->mission transition, on every machine, INCLUDING the machine's own peer entry. Downstream symptoms look like sync/render bugs: post-transition re-apply walks find nothing (`offhand_entries=0`), receivers report `no-store-for-wearer`, cosmetics/state "reset" when leaving the keep even though no peer left.

**Diagnosis pattern.** Vanilla logs `PlayerManager:remove_player peer_id=<p> <lpid>` per player per transition (own peer + remote peers + bots). If your purge log line follows those at map-change time, this class - not a disconnect, not a wire loss. Hard evidence: cosmetics 2026-07-06 17:28:20.460/.471 (host removed ITSELF then the client during a keep->mission load; both store entries wiped; client mirrored at 17:28:17.531).

**Fix template.** Never purge synchronously in `remove_player`. Defer with a deadline (cosmetics uses 30s) and cancel in a `PlayerManager.add_remote_player` hook_safe - transitions re-add peers within seconds, genuine disconnects never do. Skip the local peer entirely. See cosmetics_tweaker 0.9.71-dev `[la-state] PEER-PURGE scheduled/canceled/executed`.

**Related.** A second transition-window class rides along: RPCs sent to/from a peer that is mid-load are dropped silently with no error (same session: three client->host packets between 17:28:26-17:28:55 never arrived; keep-time round-trip was 98ms). Any "send once on state change" design must retry-until-acked or pull-on-ready-with-ack (cosmetics `cos_la_state_req`/`cos_la_state_ack`).

---

## 25. Bot guard scoped to the follow target is blind to downed teammates (follow-set drops the disabled BEFORE the guard runs)

**First seen:** 2026-06-29 (gt_dev #139, v0.2.148/.152 partial fixes); v0.2.185-dev blanket veto user-confirmed once, then reopened 2026-07-09; v0.2.243-dev carries correlated diagnostics because the recurrence is not yet attributed
**Canonical Issue:** [#139](https://github.com/Ensrick/vermintide-2-tweaker/issues/139) (bots teleport AWAY from downed players)
**Lives in:** any bot-AI guard, veto, or probe that reads the bot's CURRENT follow/move target (`blackboard.ai_bot_group_extension.data.follow_unit`) to decide something about "the teammate the bot cares about"

### Symptoms
- A bot behaves as if a downed/disabled teammate does not exist: it teleports or leashes toward a *living* far player instead of pathing in to revive the one who just went down.
- The bug only manifests when the team is **split** (someone down here, a living player far away). With everyone bunched, or with only one human left standing, the same guard "works" - because the follow target happens to be the downed player.
- A follow-scoped diagnostic (`[gt_bot:139] TELEPORT executed (follow downed=...)`) reports `follow downed=false` at the exact moment the bug fires, because by then `follow_unit` has already flipped to the living player - so the probe *looks* like the fix is working while the bot abandons the downed teammate.

### Diagnosis pattern
1. Read the vanilla follow-set builder: `AIBotGroupSystem._update_move_targets` (`ai_bot_group_system.lua:680`) splits players into non-disabled (`TEMP_PLAYER_UNITS`) and disabled (`TEMP_DISABLED_PLAYER_UNITS`) at `:695-708`, then swaps the disabled list in **only when `num_units == 0 and num_disabled_units > 0`** - i.e. every human is down (`:713-719`). So on any partial down, disabled players are *dropped* from the follow-candidate set and `follow_unit` becomes a living player.
2. Therefore any guard that reads `follow_unit` (or `data.follow_unit`) to find "the teammate needing help" is structurally blind - the disabled teammate was removed one step upstream, before the guard ran.
3. Confirm by scoping the check to the unfiltered SIDE roster instead: `Managers.state.side.side_by_unit[bot_unit]:player_units()` (`side.lua:222`), iterating all teammates and testing each with the full aid/rescue predicate. If the side-scoped check sees the down but the follow-scoped one does not, this class. `side.PLAYER_UNITS` is insufficient because `SideManager._update_frame_tables` filters awaiting-rescue units out (`side_manager.lua:338-340,371-405`).

### Fix template
Scope the aid/veto helper to the bot unit + `side:player_units()`, never the follow target. gt's `_gt_any_side_teammate_needs_aid(self_unit)` delegates to the full disabler/awaiting-rescue predicate; the veto is applied to the FINAL `should_teleport` decision so it catches vanilla's 40 m teleport and the mod's tighter leash. Diagnostics must retain identity across selector, veto, and action: `[gt:139:chain] FOLLOW` records the final post-override follow target, `VETO` records bot + aid + follow, and `TELEPORT` reports the recent veto age plus #492 bailout state. Sample the action's immediate position with `Unit.world_position`; `POSITION_LOOKUP` can remain stale until the following system tick.

```lua
-- WRONG -- follow_unit already flipped to a living player on a partial down
local target = blackboard.ai_bot_group_extension.data.follow_unit
if target and _needs_aid(target) then ... end   -- blind to the downed teammate

-- RIGHT -- scan the side's unfiltered player roster
local side = Managers.state.side.side_by_unit[self_unit]
for _, u in ipairs(side:player_units()) do
    if u ~= self_unit and _gt_unit_needs_aid_or_rescue_full(u) then ... end
end
```

### Residual blind spots (do NOT assume covered)
- **Selector/veto/action are different instants.** A valid veto can be followed by a later action after the aid state clears, changes ally, or #492 deliberately releases an unreachable pursuit. Timestamp-only lines from two bots cannot distinguish these paths; preserve bot and ally identity through a bounded correlation record.
- **#492 composition is intentionally behavior-changing.** The unreachable-aid watchdog steps the veto aside. A teleport with `bailout=true` is not evidence that the full aid predicate failed; it is evidence to audit the watchdog decision and regroup target separately.

### Reference fix
gt_dev `_gt_bot_fixes.lua` blanket veto in `BTConditions.should_teleport` (v0.2.185), broadened `side:player_units()` predicate (v0.2.212, #384), and `_gt_bot_teleport_lab.lua` correlated `[gt:139:chain]` trace (v0.2.243). Runtime checks: `gt_bot139_*`, `gt_bot384_needs_aid_or_rescue_predicate`, `issue139_aid_trace_correlation`; offline `test_gt_teleport_loop_policy.lua`. Related: class 21 (`POSITION_LOOKUP` dead/stale outside its owning system phase).

---

## 26. Collapsing `and`/`or` guard in a hook wrapper (condition/flag reads as a stuck constant)

**First seen:** 2026-07-06 (gt_dev #275 Creature Spawner Drachenfels/Nurgloth phase hook; fix v0.2.191-dev, closed v0.2.193-dev)
**Canonical Issue:** [#275](https://github.com/Ensrick/vermintide-2-tweaker/issues/275) (Nurgloth final-phase-at-full-health softlock on The Enchanter's Lair)
**Lives in:** any `mod:hook(C, m, ...)` whose body is `return (in_scope and func(...)) or fallback` when vanilla `C.m` legitimately returns `false`/`nil` (BT conditions, ownership/eligibility predicates, any boolean-returning vanilla fn)

### Symptoms
- A hooked system behaves as if a condition/flag is stuck at a constant value — a vanilla-IMPOSSIBLE state (e.g. a boss BT branch entered with its gating condition provably `false`; a phase machine that never advances or advances instantly).
- The bug is TOTAL, not intermittent: the guard is constant-true (or constant-`fallback`) on EVERY evaluation, so the feature is "always broken" rather than "sometimes broken" — which misdirects investigation toward whatever unrelated feature was toggled (13 attempts on #275 chased gut Skip Cutscenes and two wrong level-key identifications before the hook was read).
- No error, no crash log — the wrapper returns a valid-typed value, just the wrong one.

### Diagnosis pattern
1. When a boss / AI **phase machine** misbehaves, grep the ENTIRE active mod stack for `mod:hook(BTConditions` / `"BTConditions"` FIRST — BT conditions are name-resolved on EVERY evaluation (`bt_node.lua:55-57`), so a single collapsed guard poisons every tick with no caching to mask it.
2. Read the hook body. The tell is a boolean tail: `return (in_scope and func(...)) or <literal>`. Look up the wrapped vanilla fn in `Vermintide-2-Source-Code` — if it legitimately returns `false`/`nil` as a MEANINGFUL result, the `or <literal>` overwrites it with the literal every time that case fires.
3. Two failure sub-modes fold into one idiom: (a) the boolean collapse above; (b) multi-RETURN truncation — `(cond and func(...))` only forwards `func`'s FIRST return into the `and`, dropping the rest (distinct precedent: class 2, "Hook wrapper multi-return collapse").

### Fix template
Branch explicitly; never lean on `and`/`or` to route a vanilla return you care about.
```lua
-- WRONG -- (true and false) or true == true; the false case is unreachable,
--          and any 2nd/3rd return of func is dropped.
mod:hook(BTConditions, "transitioned_one_third_health", function(func, ...)
    return (_gt_cs_is_in_level("dlc_castle") and func(...)) or true
end)

-- RIGHT -- explicit branch; in-scope returns vanilla UNALTERED (multi-return
--          preserved), out-of-scope returns the intended fallback.
mod:hook(BTConditions, "transitioned_one_third_health", function(func, ...)
    if _gt_cs_is_in_level("dlc_castle") then return func(...) end
    return true
end)
```
Then sweep the repo for the idiom: `\(.*and func\(.*\)\) or ` across every active mod's hooks. Not every match is a bug — the `or <default>` tail is harmless when the defer branch returns a truthy BT-status string / table / discarded value (gt's v0.2.191 sweep cleared `BTSpawnAllies.run`, `BTLootRatFleeAction.{enter,run,leave}`, and the navmesh-query guards on that basis). It is ONLY a bug when the wrapped fn's `false`/`nil` is a meaningful result. Back the fix with a truth-table regression check wired to the SAME helper the hook calls (gt: `gt_cs_transitioned_one_third_not_forced`).

### Related Issues / commits
- Issue [#275](https://github.com/Ensrick/vermintide-2-tweaker/issues/275) — misattributed to cutscene skipping for ~13 attempts; root cause was this collapse in `_gt_creature_spawner.lua`. Fix commit `b166251`.
- Probe evidence (`[et:275]` breed-field-wrapped blackboard probe, 2026-07-06 author log): `[et:275] HOOK sorcerer_drachenfels_go_offensive_intense | hp_pct=1.000 ... two_thirds_done=nil one_third_done=nil` — final-offense phase entered at full health, transitions never flagged.
- `general_tweaker_dev/CHANGELOG.md` v0.2.191-dev (fix + repo idiom sweep + `gt_cs_transitioned_one_third_not_forced` check), v0.2.193-dev (#275 close-out).
- `general_tweaker_dev/POSTMORTEMS.md` — full #275 timeline (why the probe had to be breed-field-wrapped; why BT hooks must wrap before `create_all_trees`).
- Related: class 2 (multi-return collapse via `return wrapper(func(...))`) — same "don't route a vanilla return through an expression" root, different operator.

## 27. Husk resolves the BASE item_data, never the CWV instance (owner-path logic cannot reach a remote player)

**First seen:** 2026-07-06 (CWV husk-cluster ship v0.1.366-dev; residual gaps hardened v0.1.367-dev)
**Canonical Issue:** [#392](https://github.com/Ensrick/vermintide-2-tweaker/issues/392) (husk base-resolution umbrella); sub-classes [#280](https://github.com/Ensrick/vermintide-2-tweaker/issues/280) (client CTD), [#396](https://github.com/Ensrick/vermintide-2-tweaker/issues/396)/[#401](https://github.com/Ensrick/vermintide-2-tweaker/issues/401) (invisible/wrong husk mesh), [#397](https://github.com/Ensrick/vermintide-2-tweaker/issues/397)/394 (husk transform not applied), [#399](https://github.com/Ensrick/vermintide-2-tweaker/issues/399) (inherited ammo mesh on husk), 395/398 (stale unequip / sounds)
**Lives in:** any mod that clones a base weapon into a new item but keeps `entry.name = base_weapon` (the CWV "clone-name-clobber", `feedback_cwv_clone_name_clobber.md`). Applies to every cross-character / duplicate-item mod (CWV, weapons_of_chaos, any future clone-a-template mod).

### Symptoms
- A modded weapon looks / behaves correctly for the LOCAL wielder and their BOTS, but on a REMOTE player (husk) it is invisible, renders the wrong (base) mesh, wrong scale, an extra inherited ammo/torpedo mesh, or (worst) CTDs every non-source-character client.
- The bug is peer-relative: peer A (playing the source character, e.g. Kruber) sees it fine; peer B (playing anyone else) sees the break. Single-player and host-only testing never reproduces it.

### Diagnosis pattern
1. The equipment RPC encodes an item by `NetworkLookup.item_names[item_data.name]`. A CWV clone keeps `entry.name = base_weapon`, so the wire carries the BASE key. The husk looks up the VANILLA `ItemMasterList[base_weapon]` and knows nothing about the CWV instance — no `cwv_variant` marker, no `cwv_<key>_001` backend_id, only whatever `slot.skin` (a real `NetworkLookup.weapon_skins` entry) happened to sync.
2. Therefore **every owner-path fix is invisible to husks.** Owner/bot spawns go through `GearUtils.create_equipment` (1P rig present); husk spawns go through `SimpleHuskInventoryExtension._wield_slot -> GearUtils.spawn_inventory_unit` with `owner_unit_1p == nil`. A hook that only touches `create_equipment`, or reads `item_data.backend_id`/`.cwv_variant`, never fires for the husk.
3. The ONLY husk-reachable signals are: the synced `item_units.skin` (present when a curated illusion is applied), and a POSITIVE base+career inference (a base weapon on a career that CANNOT natively wield it — e.g. dwarf-exclusive `dr_deus_01` on a Kruber can only be the CWV Outrider). `item_data.name` alone is NOT a usable signal — it collides with a genuine native wielder of the real base weapon.

### Fix template
Put husk fixes in the `GearUtils.spawn_inventory_unit` hook, gated on `not owner_unit_1p`, resolving the CWV def only via positive signals:
```lua
mod:hook("GearUtils", "spawn_inventory_unit", function(func, world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, ...)
    local v_w3p, v_a3p, v_w1p, v_a1p = func(world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, ...)
    if not owner_unit_1p then                 -- husk/bot discriminator (no 1P rig)
        -- (a) strip inherited ammo only on a base+career POSITIVE match (issue 399)
        -- (b) apply scale/offset only when a cwv-positive signal resolves a def (issue 397);
        --     log-once when it can't (issue 392 evidence) — never guess from item_data.name
    end
    return v_w3p, v_a3p, v_w1p, v_a1p
end)
```
Residency is the other half: the mesh the husk will spawn (curated-skin override units == `def.right_hand_unit`/`.left_hand_unit`) must be RESIDENT on every client. Force-load override units that DIFFER from the base, data-driven over all defs, ref-held at boot — NOT a mission-load blanket load (class: 1 GiB Lua-heap), and ONLY vanilla `units/weapons/player/` paths (class 28: a mod-bundled mesh queued into `Managers.package:load` is an uncatchable boot fatal). Keep the vanilla base-unit force-load as the issue-280 crash floor and a general `start_weapon_fx` nil-slot guard as the durable crash net. Fixes that require the husk to resolve the CWV INSTANCE (transform on a skinless/cim-crafted equip; template-level sound swaps) are blocked until #392 gives the husk a way to see the CWV item (net-safe skin/marker on the wire).

### Fix sites (v0.1.366-dev / v0.1.367-dev, `character_weapon_variants.lua`)
- `SimpleHuskInventoryExtension.start_weapon_fx` guard — durable nil-slot crash net (issue 280).
- `dr_shield_axe` base-unit force-load — issue-280 crash floor (base-path spawn).
- Data-driven override-unit residency pass (`_om._husk_override_unit_needs_residency`) — issues 396/401, covers all 27 override-differ variants by construction.
- `spawn_inventory_unit` husk block -> `_om._husk_strip_cwv_ammo` (issue 399) + `_om._husk_apply_cwv_transform` (issue 397), throttled `[cwv husk-transform] no cwv def resolved` log = the #392 evidence arm.
- Regression tests `cwv_husk_override_residency`, `cwv_no_ammo_strip_coverage`, `cwv_husk_transform_coverage`.

### Related Issues / commits
- v0.1.366-dev ship commit `ff8fa2c`; hardening in v0.1.367-dev (`character_weapon_variants/CHANGELOG.md`).
- Full mechanism + audit table (which variants are covered, which await #392) in `character_weapon_variants/DEVELOPMENT.md` "Husk rendering path".
- Related: class 5 (self-owned vs husk extension classes are separate roots) — same "hook the path the husk actually takes" root.

## 28. Mod-bundled unit path queued into `Managers.package:load` = uncatchable async boot fatal

**First seen:** 2026-07-07 (CWV v0.1.367-dev — game could not boot at all)
**Canonical Issue:** [#403](https://github.com/Ensrick/vermintide-2-tweaker/issues/403)
**Lives in:** any residency/force-load pass that derives load targets from item defs (CWV, wt cross-char ports, cosmetics preloads)

### Symptoms
- Engine fatal seconds into startup on EVERY launch (game unbootable), no Lua crash block from the mod itself. Crash log shows `<<Script Error>><unit path>` with a stack in `PackageManager._pop_queue` / `force_load` (`foundation/scripts/managers/package/package_manager.lua:194/137`) called from `boot.lua` — not from any mod file.
- The mod's own load-time printf for the offending path reported SUCCESS (`force-loaded ... resident=false`).

### Diagnosis pattern
1. `Managers.package:load(path, ref, nil, true, true)` only QUEUES an async load — a pcall around it always succeeds. The fatal fires LATER when the queue pops the entry and the engine finds no such resource package. Nothing in Lua can catch it (same family as class 22's uncatchable AV).
2. Vanilla per-weapon meshes under `units/weapons/player/...` ARE loadable as per-unit packages (proven: CWV residency passes across many sessions). A MOD-BUNDLED unit (`units/<mod>_.../...`, built into the mod's own bundle) is NOT an engine package — queuing it (or any derived `.."_3p"` sibling) is the fatal.
3. Fingerprint: the `<<Script Error>>` path matches a `right_hand_unit`/`left_hand_unit` value in a mod def whose mesh ships in the mod bundle.

### Fix template
Filter the load predicate to vanilla weapon paths only; mod-bundled meshes are resident wherever the mod is installed and never need force-loading:
```lua
if u:find("units/weapons/player/", 1, true) ~= 1 then return nil end
```
Keep the predicate SHARED between the loader and its regression test so the assertion tracks the filter.

### Related Issues / commits
- #403 hotfix cwv v0.1.368-dev; the sweep that exposed it: v0.1.367-dev data-driven residency (class 27).
- Memory: `reference_vt2_package_load_needs_package_not_unit_path` (the general "unit path = async crash" rule; this class adds the vanilla-weapon-path exception and the mod-bundle trap).

## 29. Client-side buff proc calls a server-only DamageUtils API (`heal_network` fassert "Only server can heal")

**First seen:** 2026-07-07 (crt Fires from Ash THP, client session; sweep found ct's kill-heal boon same day)
**Canonical Issue:** [#405](https://github.com/Ensrick/vermintide-2-tweaker/issues/405) (crt), [#406](https://github.com/Ensrick/vermintide-2-tweaker/issues/406) (ct/ct_dev)
**Lives in:** any mod-added or mod-wrapped buff proc / BuffFunctionTemplates function that grants healing (or other server-authoritative effects) — crt/ct/et Big Rebalance reworks, CW power-ups

### Symptoms
- A CLIENT hard-crashes mid-mission the moment a proc fires (e.g. on their own kill): `fassert "Only server can heal"` from `damage_utils.lua:2636`, stack through `buff_extension.lua trigger_procs` into the mod's buff_func. HOST-side play never reproduces — the bug ships and survives until the author first plays as a client with the toggle/boon active.

### Diagnosis pattern
1. `trigger_procs` runs on the killer's/actor's LOCAL machine — on_kill/on_hit procs fire with `is_server = false` on clients.
2. `DamageUtils.heal_network` (and its siblings) fasserts server authority. EVERY vanilla `heal_from_proc` call site is gated `Managers.player.is_server` (`buff_templates.lua:313-328, :404`) or `Managers.state.network.is_server` (`:435+`). A wrapper that copies the heal but drops the gate is this class.
3. The heal is not lost by gating: the host also triggers the same proc for a client's kill (server-side buff instance), so the host instance grants the heal — vanilla's exact semantics. (Requires the host to run the mod; degraded-not-crashed otherwise.)

### Fix template
```lua
if not (Managers and Managers.player and Managers.player.is_server) then return end
DamageUtils.heal_network(owner_unit, owner_unit, amount, "heal_from_proc")
```

### Related Issues / commits
- #405 hotfix crt v0.3.53-dev; #406 hotfix ct_dev v0.7.237-dev (STABLE ct carries it until promotion).
- Sweep rule: on finding one, grep every mod for `heal_network(`/`add_damage_network(` and audit the gates (enemy_tweaker's two procs were already correct).

## 30. Modded craft intercept assumes `recipe_override` is always non-nil (true on M+K, false on the console/gamepad craft-item page)

**First seen:** 2026-07-07 (cim_dev: no CWV weapon could be crafted on a gamepad)
**Canonical Issue:** [#407](https://github.com/Ensrick/vermintide-2-tweaker/issues/407) (cim/cim_dev)
**Lives in:** any mod that hooks `BackendInterfaceCraftingPlayfab.craft` (or `CraftingManager.craft`) and branches on `recipe_override`, replacing the PlayFab roundtrip with local synthesis. cim's standard forge is the instance.

### Symptoms
- Crafting works fine on mouse+keyboard but EVERY craft is silently dropped on the console/gamepad crafting UI. In cim the tell is the chat warning "Craft dropped - no recipe selected (recipe_override=nil)" and `[craft_attempt] recipe=nil` on windows named `HeroWindowCrafting*Console`. The user reads it as "CWV items won't craft" but it drops vanilla items too.
- Input-mode-relative, not item-relative: the same template crafts on M+K and drops on a controller. Testing on only one input mode never reproduces the other.

### Diagnosis pattern
1. Vanilla `_get_valid_recipe(item_backend_ids, recipe_override)` (backend_interface_crafting_base.lua:27-51) has TWO modes: a non-nil override validates that one recipe; a **nil** override AUTO-DETECTS by iterating every recipe and returning the first whose validation passes.
2. The two UIs feed it differently. PC "Craft Item" passes the recipe explicitly (`parent:craft(items, self._recipe_name)`, craft_page_craft_item.lua:322). The **console** "Craft Item" passes NONE (`parent:craft(items)`, craft_page_craft_item_console.lua:325) and leans on the auto-detect. (Only the craft-item console page does this; salvage/reroll/apply-skin/upgrade/extract/convert consoles all pass `self._recipe_name`.)
3. A mod that intercepts `craft` cannot fall through to vanilla `func` in modded realm (it enqueues the EAC-gated PlayFab request -> `playfab_eac_error` reason 511 -> kick). So a hook that early-drops on `not recipe_override` kills every console craft-item.

### Fix template
When `recipe_override` is nil, re-derive it locally from the dropped item's `slot_type` (the same choice vanilla setup_recipe_requirements makes, craft_page_craft_item_console.lua:80-84) instead of dropping — then proceed through the mod's own recipe/synth path:
```lua
if not recipe_override then
    local bid1 = item_backend_ids and item_backend_ids[1]
    local slot = bid1 and Managers.backend:get_interface("items"):get_item_masterlist_data(bid1)
    slot = slot and slot.slot_type
    recipe_override = mod._craft_item_recipe_for_slot(slot)   -- melee/ranged->craft_weapon, jewelry->per-slot synth
end
if not recipe_override then return _silent_drop(...) end       -- only NOW is a nil override a real user error
```

### Related Issues / commits
- #407 fix cim_dev v0.8.53-dev (`standard_forge.lua` craft() hook + `mod._cim407_craft_item_recipe_for_slot`). STABLE cim carries it until promotion.
- Regression: `/cim_regression_test` -> `console_craft_item_nil_recipe_resolves`.
- Related: class 27 (#390 crafted-CWV base-render) — same feature (cim crafting a CWV variant), different failure stage (this one blocks the craft entirely; 27 is the post-craft render).

## 31. Cross-peer wire crash-safety coupled to a feature toggle (a fix that got un-gated re-exposes the crash by default)

**First seen:** 2026-07-07 (cim issue 278 recurrence; fixed cim v0.8.34 / cim_dev v0.8.54-dev)
**Canonical Issue:** [#278](https://github.com/Ensrick/vermintide-2-tweaker/issues/278) (the crash); [#371](https://github.com/Ensrick/vermintide-2-tweaker/issues/371) (the all-mods never-crash mandate + auto-gate framework)
**Lives in:** any mod that appends a modded entry to a networked lookup table and relies on a SENDER-side substitution to keep that entry off a vanilla RPC — cim (rarities), cwv (item_names), cosmetics (weapon_skins), and anything future that clones/registers networked content.

### Symptoms
- A peer who does NOT have the mod hard-CTDs when a peer who DOES have it performs a routine action (equip a crafted item, wield a cross-char weapon). Peer-relative: the mod-haver is fine; the non-mod peer dies. Single-player / all-peers-have-the-mod testing never reproduces it.
- Reproduces with DEFAULT settings — because the safety was gated behind a toggle that defaults OFF.

### Diagnosis pattern
1. The mod appends a modded key to a networked table (`NetworkLookup.rarities["modded"]`, `item_names[cwv_key]`, `weapon_skins[skin_key]`) and that index rides a VANILLA RPC (`rpc_sync_loadout_slot`, equipment/skin sync). A non-mod peer's table lacks the append, so the reverse-lookup returns nil and a downstream deref fatals (`RaritySettings[nil].order`, `loadout_utils.lua:73`) or the strict `__index` throws (`network_lookup.lua:2521`).
2. The mod already HAD the sender-side fix (swap the modded key for a vanilla one before encode). The regression is that a later refactor **bundled the safety rewrite behind an unrelated feature toggle** (cim's `persist_modded_loadouts`, default OFF) on the false premise that "toggle off == behave exactly like vanilla." That premise never holds for wire safety: the live loadout still carries the modded value regardless of the toggle, so toggle-off ships the raw modded key onto the wire.
3. A RECEIVER-side guard on the same RPC does NOT help: it runs on a peer that HAS the mod, but the crashing peer is the one WITHOUT it. Only a sender-side (host) substitution protects a non-mod peer.

### Fix template
Single-source the coercion in a PURE helper that takes NO toggle argument (so it is structurally ungateable), call it unconditionally on the send path, and let the toggle gate only the cosmetic/persistence half:
```lua
local function _cim_wire_safe_rarity(rarity)   -- no persistence arg by construction
    if rarity == "modded" then return "unique" end
    return rarity
end
-- in the LoadoutUtils.sync_loadout_slot hook:
if is_modded then
    local original = item.rarity
    item.rarity = _cim_wire_safe_rarity(original)   -- ALWAYS, regardless of any toggle
    pcall(func, ...)
    item.rarity = original
end
```
Assert it in the regression suite with a check that the coercion is correct AND takes no toggle argument (`wire_rarity_rewrite_ungated`).

### Related Issues / commits
- cim v0.8.34 (public hotfix) + cim_dev v0.8.54-dev; commits `cd64fa8` / `02e9d69`.
- Memory: `reference_vt2_wire_safety_never_toggle_gated`.
- Related: class 27 (husk resolves BASE item_data — the render-side twin of the same "clone keeps base identity on the wire" root); the general gated-registration cold-read crash (`rawget` section near the top of this file).

## 32. Cleanup-on-teardown dispatches into a destroyed World (LineObject/Gui use-after-free that pcall cannot catch)

**First seen:** 2026-07-11 (gt_dev issue 459; fixed gt_dev v0.2.196-dev)
**Canonical Issue:** [#459](https://github.com/Ensrick/vermintide-2-tweaker/issues/459)
**Lives in:** any mod that caches a World handle plus a world-owned engine object (LineObject, screen Gui) in mod fields and "cleans up" from a per-frame path (mod.update consumer or class hook) — gt_dev bot teleport lab + debug highlights; the template for every future debug-draw overlay.

### Symptoms
- Deterministic hard CTD (C-level access violation, e.g. `0xc0000005` at a low offset like `@0x160`) on Leave Game / state transition while an overlay toggle is on. No Lua crash block — the fatal is native.
- The crashing call is wrapped in `pcall` and crashes anyway: pcall catches Lua errors, not a C-level AV on its own stack.

### Diagnosis pattern
1. VMF `mods_update` keeps ticking OUTSIDE game states (boot.lua `game_update` -> mod_manager), so per-frame mod draw/cleanup code runs while `StateIngame.on_exit` is mid-teardown.
2. `on_exit` ordering: `PlayerManager.exit_ingame` nils `is_server` (player_manager.lua:180) five lines BEFORE `_teardown_world` destroys the level world (state_ingame.lua:719) — so a "not `Managers.player.is_server`" branch that tears down cached draw resources runs exactly when the cached handles are freed.
3. `LineObject.reset` / `LineObject.dispatch` / Gui calls on the freed handles are a native use-after-free. Vanilla never hits this: engine code only dispatches into live worlds (navigation_group_manager.lua:843, debug.lua:419 clean up while the world is alive).
4. Grep the mod for cached handles: `mod._*_line_object`, `mod._*_line_world`, `mod._*_gui`, plus any bare `Managers.world:world("level_world")` on a per-frame path.

### Fix template
```lua
local function _clear_and_null()
    local lo = mod._line_object
    local w  = mod._line_world
    if lo and w then
        local wm   = Managers.world
        local live = wm and wm:has_world("level_world") and wm:world("level_world")
        if live == w then          -- IDENTITY, not mere existence
            pcall(function()
                LineObject.reset(lo)
                LineObject.dispatch(w, lo)
            end)
        else
            _pf("[mod:NNN] skipped LineObject cleanup - cached world is dead")
        end
    end
    mod._line_object = nil   -- ALWAYS drop the handles: a destroyed world
    mod._line_world  = nil   -- already freed its line objects
end
```
- The **identity comparison is load-bearing**: `has_world` alone passes when a NEW same-named world exists while the cached handle still points at the freed old one (mission -> mission transition).
- **Cleanup-on-teardown is itself a use-after-free path.** "Release engine resources before dropping references" is the WRONG instinct once the owning world is gone; dropping the Lua references IS the correct teardown.
- Companion fassert exposure: `WorldManager.world()` **fasserts** on a missing world (foundation/scripts/managers/world/world_manager.lua:111-115). Every `Managers.world:world("level_world")` on a mods_update-driven path must probe `has_world` first — and a nil check placed AFTER the bare call is dead code.

### Related Issues / commits
- gt_dev v0.2.196-dev (#459): `_gt_bot_teleport_lab.lua` `_clear_and_null` (the crash) + `_gt_debug_highlights.lua` `_clear` (byte-identical latent twin); regression check `gt_459_lineobject_cleanup_liveness_gated`.
- Related: class 21 (POSITION_LOOKUP dead in mod.update — same "mod code ticks where vanilla state is stale/gone" root), class 23 (Gui material residency draw fatal — the create-side twin of this dispatch-side fatal), class 12 (Vector3/Quaternion stack-temporary lifetime).

## 33. Update-loop consumer calls a network-gated PlayerManager API before the backend exists

**First seen:** 2026-07-12 (gt_dev issue 508; fixed gt_dev v0.2.200-dev)
**Canonical Issue:** [#508](https://github.com/Ensrick/vermintide-2-tweaker/issues/508)
**Lives in:** any per-frame mod code (mod.update consumer, VMF update callback) that resolves the local player. VMF ticks mods in the boot/menu phase too (same root as class 32: mod code runs where vanilla state does not exist yet).

### Symptoms
- `[MOD][<mod>][ERROR] ... player_manager.lua:NNN: Network backend has not been set` once per frame (60/s) at boot or main menu, stopping only when a game session starts. No crash - error spam, chat-visible when routed through `mod:error`/`mod:warning`.
- Trigger is a persisted-ON toggle whose per-frame path resolves the player before checking game state.

### Diagnosis pattern
1. `PlayerManager.local_player` has NO readiness guard - it goes straight to `Network.peer_id()` (player_manager.lua:580-586), which asserts before the network backend is initialized.
2. Vanilla's own answer sits right below it: `local_player_safe` (player_manager.lua:588-596) returns nil unless `Managers.state.network` exists AND `network:game()` is live.
3. Grep the mod for `:local_player()` on any update-consumer path.

### Fix template
- Replace `pm:local_player()` with `pm.local_player_safe and pm:local_player_safe()` on every per-frame path; treat nil as "not in a session yet" and bail. In-session behavior is identical - once a player unit exists both calls resolve the same player.
- Harden the update dispatcher: log one line per DISTINCT consumer error per streak (re-arm on success or message change), never one per frame - a recoverable boot-phase failure must not flood chat/log (gt_dev `mod.update`, v0.2.200-dev).

### Related Issues / commits
- gt_dev v0.2.200-dev (#508): `_gt_debug_highlights.lua` `_local_player_unit` + dispatcher suppression; regression check `gt_dh_local_player_safe_508`.
- Related: class 21 / class 32 (the "VMF ticks outside game states" family); `docs/engine/03` network readiness.

## 34. Bot-BT recovery keyed to a timer or one-shot latch that outlives the failure window

**First seen:** 2026-07-12 (gt_dev issues 492 + 515; fixed v0.2.202/.203-dev; both user-verified Fixed same day)
**Canonical Issues:** [#492](https://github.com/Ensrick/vermintide-2-tweaker/issues/492), [#515](https://github.com/Ensrick/vermintide-2-tweaker/issues/515)
**Lives in:** any bot behavior-tree intervention that (a) bounds a stuck state with a wall-clock timer, or (b) relies on a vanilla one-shot flag it never re-arms.

### Symptoms
- The intervention "works" in testing but is useless live: the recovery fires long after the situation resolved itself (a downed player is often dead in under 5s; a 35s no-progress bound acted on corpses — the #492 rejection).
- A capability works exactly once per mission: vanilla `has_teleported` (bt_bot_teleport_to_ally_action.lua:93) is cleared ONLY in `BTBotFollowAction.enter` (bt_bot_follow_action.lua:14), so a bot that never re-enters the follow node holds the latch forever (#515 gap 1).

### Diagnosis pattern
1. Ask what the timer is actually protecting against (usually decision thrash) and whether the engine already computes the failure signal — vanilla records aid-path failure per ally in `cb_ally_path_result` (player_bot_base.lua:1911-1934) and treats 3-12s as "give up" (bt_bot_conditions.lua:1203, player_bot_base.lua:1943-1946). A mod timer far outside that band is wrong by inspection.
2. For any vanilla one-shot flag your feature depends on, grep every site that CLEARS it; if clearing lives in one BT branch, your feature dies the first time the bot takes a different branch.

### Fix template
- Replace long timers with the engine's own failure verdicts (path-failed callbacks) plus a short distance-gated no-progress backstop; justify every constant against the vanilla band and the human-relevant window (bleedout timings).
- Prevent thrash with HYSTERESIS (bail at >FAR, re-engage under <NEAR, FAR > NEAR), not with a long timer; latch the bail and un-latch only on a real state change (target no longer needs aid / genuinely close again).
- Re-arm one-shot vanilla latches under your toggle on a short cooldown inside the vanilla give-up band, leaving the downstream gates to veto the actual action.
- Make every branch observable: per-event printf with a roster census so a field log settles WHICH condition held (`[gt:492]` / `[gt:515]` lines).

### Related Issues / commits
- gt_dev v0.2.202-dev (#492 rework: 4s path-fail + 8s no-progress + hysteresis latch; census printfs), v0.2.203-dev (#515: latch re-arm, backward bypass on the aid node, 492-bailout composition). Regression checks `gt_bot492_aid_stall_recovery`, `gt_bot515_teleport_latch_rearm`, `gt_bot515_cant_reach_backward_bypass`.
- Related: #139/#142 (bot follow/teleport family), class 21 (stale state in mod-update phases).

## 35. Force-loaded weapon `_3p` package under a shared "global" ref, never released — shutdown "not unloaded" deadlock + in-mission "locking a resource about to be unloaded"

**First seen:** 2026-07-03 (cross-mod CW session; cosmetics-owned slice fixed v0.9.76-dev)
**Canonical Issue:** [#282](https://github.com/Ensrick/vermintide-2-tweaker/issues/282) (the single tracker — its title covers wt/cwv/cosmetics; cosmetics slice re-fixed v0.9.148-dev, wt/cwv/woc slice benign/deferred); [#477](https://github.com/Ensrick/vermintide-2-tweaker/issues/477) (owner-pin evidence)
**Lives in:** any mod that force-loads a weapon/fx `_3p` package via `Managers.package:load(path, "global", ...)` on boot or cross-char wield without a paired release on level-exit/unwield/mod-unload — cosmetics Material-Hijack, wt/cwv cross-char force-loads.

### Symptoms
- Shutdown after a mission: thousands of `[PackageManager] Unload: <pkg>, global -> Package still referenced, NOT unloaded`, then crashify `'#ID[...]' not unloaded, this can potentially cause an deadlock!`, non-zero exit.
- In-mission precursor at map transitions / weapon swaps: `[ResourceManager] Locking a resource that is about to be unloaded!`.
- Refcount balloons (92 loads of one `_3p` package in a single host session) — each wield re-loads under the shared ref with no dedupe.

### Diagnosis pattern
1. Grep the mod for `:load(` / `force_load` of `_3p` packages; the reference-name arg is the tell — a shared literal `"global"` shares one refcount across every consumer AND every mod, so nobody can safely unload.
2. Count loads vs unloads per package key over a session (a `[<mod>:282]` load/dedupe/unload ledger). Loads >> unloads = leak.
3. Confirm the release EDGE, not just its presence. Two distinct bugs live here: (a) NO release at all = a leak; (b) a release wired to the PRE-teardown `on_game_state_changed("exit","StateIngame")` notification is WORSE — that callback fires BEFORE `StateIngame.on_exit` destroys player/preview units and the world, so dropping the reference while units still consume the package parks the handle in `_delayed_packages_to_remove` (package_manager.lua:213-224). On quit-to-desktop there is no `PackageManager.update` frame between state teardown and `Managers:destroy`, so the delayed handle survives into `PackageManager.destroy` (:275-279) → the `#ID[...] not unloaded ... deadlock` crash. The release must be POST-teardown.

### Fix template
- Load exactly-once per path (a dedupe registry), under a MOD-OWNED reference name (`"<mod>_mh"`, not `"global"`), tracked in a table.
- Release only at a POST-teardown edge: a `mod:hook_safe("StateIngame", "on_exit", ...)` post-call (vanilla has already destroyed units + world, so `can_unload` is true → immediate free, never delayed), plus `mod:on_unload` and previewer-destroy. NEVER release at the pre-teardown `on_game_state_changed("exit","StateIngame")` notification — that is the #282 regression (fixed cosmetics v0.9.148-dev).
```lua
if _mh_loaded[path] then return end          -- exactly-once
Managers.package:load(path, "cosmetics_tweaker_mh")
_mh_loaded[path] = true
-- teardown (POST-world; StateIngame.on_exit is a post-call hook_safe):
mod:hook_safe("StateIngame", "on_exit", function(self, application_shutdown)
    for p in pairs(_mh_loaded) do
        Managers.package:unload(p, "cosmetics_tweaker_mh"); _mh_loaded[p] = nil
    end
end)
```
- Ledger the load state as `held` vs `release_pending` and reconcile against `_delayed_packages_to_remove` in `mod.update`, so a still-delayed handle stays observable until the engine actually frees it (postcondition: no mod-owned package remains delayed when `PackageManager.destroy` begins).
- Regression: runtime check that the registry holds at most one reference per path (`mh_package_single_reference`) AND that nothing mod-owned is left in the delayed queue post-`StateIngame.on_exit`.

### Related Issues / commits
- cosmetics_tweaker v0.9.76-dev (#282 cosmetics slice, exactly-once load); **regressed 2026-07-18 (pre-teardown release edge) → re-fixed v0.9.148-dev by moving the release to `StateIngame.on_exit` post-hook.** wt/cwv/woc force-load slice tracked under **#282** (session-resident leaks that NEVER call `unload` mid-session, so they never enter the delayed queue and `destroy()` cleans them at shutdown — benign; hardening only, deferred).
- Related: class 27/28 (residency half of the same cross-char force-loading).

## 36. Self-heal / seed-repair writes across the modded-official realm boundary (modded ids leak into the EAC-trusted store)

**First seen:** 2026-07-06 (gut_dev #402; prevention proven + repair shipped v0.2.215-dev)
**Canonical Issue:** [#402](https://github.com/Ensrick/vermintide-2-tweaker/issues/402); regression window #375/#379/#387
**Lives in:** any mod that mirrors an official/EAC-trusted backend into a separate modded store and has a repair/seed/self-heal path that reads or refills from official (gut native-loadouts; any future modded-progression mirror).

### Symptoms
- After entering the OFFICIAL realm, saved loadouts are corrupted: a slot shows a fallback template (e.g. Blacksmith's Variant greatsword) — the signature of a MODDED item id written into official data that official can't wield -> template fallback. The equipped portrait FRAME leaks the same way (modded-injected frames invalid on official).
- One path is spared (a separate index, e.g. gut's bot loadout), which misleads triage toward the wrong subsystem.

### Diagnosis pattern
1. Every runtime write that can diverge official data from its mirror must funnel through ONE chokepoint (gut: `PlayFabMirrorBase.set_character_data`, which writes `_career_data` before delegating to `set_career_read_only_data`). Audit that the mod no-ops that chokepoint in the official realm.
2. `slot_frame` (and other cosmetic slots) are ORDINARY loadout slots via `set_loadout_item -> set_character_data`, NOT hero attributes — a weapon-only guard misses them. Cover frame + cosmetic slots.
3. The introduction is usually a NEW seed/repair/self-heal feature that reads/writes across the boundary; the corruption is residual pre-isolation data plus any un-gated write, not necessarily a live new write.

### Fix template
- Gate EVERY persist/set-through on `_in_modded_realm()`; block the write at the chokepoint in official and route to the modded store.
- Ship an OFFICIAL-realm repair command (report-only default; apply replaces only already-broken slots with an owned resolvable id; refuses in the modded realm) covering weapons AND frame/cosmetic slots.
- Regression: assert all official-write chokepoint methods stay hooked (`native_loadouts_official_write_chokepoint`) so a dropped hook re-opens the leak -> gate fails.

### Related Issues / commits
- gut_dev v0.2.215-dev (#402). Related: class 31 (wire safety — same "modded value must not reach a context that can't handle it" root, persistence axis vs wire axis); #174 (the original isolation this regression breached).

### Read-only mod-owned instance exception (#287)
`Use non-modded loadouts` must not turn a receiver-local mod-owned equip into a snap-back loop. Preserve cosmetics and exact mod-owned backend instances in a modded-only overlay while leaving the official row untouched; do not classify by slot alone. For CWV the closed identity is `^cwv_.+_%d%d%d$`, covering native and CIM-crafted variant instances without accepting arbitrary official IDs. Reads and writes must share the same predicate, including whole-loadout preview reads. Choosing an ordinary weapon clears the mod-owned overlay value and falls through to official rather than persisting the attempted ordinary ID. Regression-test modded preservation and `MODE_OFF` official inertness together.

## 37. Injected/enabled vanilla mutator indexes a per-level-conditional CurrentBossSettings field unguarded (host fatal on fixed-end-boss levels)

**First seen:** 2026-07-09 (event_tweaker #455; fixed v0.4.25-dev)
**Canonical Issue:** [#455](https://github.com/Ensrick/vermintide-2-tweaker/issues/455)
**Lives in:** any mod that injects/enables a vanilla mutator whose server dispatch function indexes a `CurrentBossSettings` sub-table only some levels build.

### Symptoms
- Host fatal `mutator_multiple_bosses.lua:8: attempt to index field 'boss_events' (a nil value)` at `mutator_handler.lua:644` on a fixed-end-boss level (e.g. The War Camp) with the mutator enabled; roaming-boss levels never reproduce.

### Diagnosis pattern
- `CurrentBossSettings` is rebuilt per level from the conflict director's `boss` block (`conflict_director.lua:879`); fixed-end-boss levels ship a boss block with no `boss_events` table. `multiple_bosses` / `blessing_of_grimnir` / `deus_pacing_tweak` all index it unguarded in their server dispatch functions.

### Fix template
- Wrap the boss-event mutators' dispatch fields at the injection chokepoint; no-op (with printf) when `boss_events` is absent, normal behavior otherwise. Guard ALL siblings, not just the reported one.

### Related Issues / commits
- event_tweaker v0.4.25-dev; regression `issue455_boss_event_mutators_guarded`. Related: #386 (scalar-pacing sanitizer — sibling injection-time guard).

## 38. Network-owner identity reused as cosmetic-wearer identity for host-owned bots

**First seen:** 2026-07-13 (cosmetics_tweaker #513 score lineup; fixed v0.9.95-dev)
**Canonical Issue:** [#513](https://github.com/Ensrick/vermintide-2-tweaker/issues/513)
**Lives in:** any UI/render path that reconstructs a wearer from a scoreboard or roster row, then keys human-only cosmetic state by `peer_id`.

### Symptoms
- One human's helmet, skin, or other per-peer cosmetic appears on unrelated bot careers owned by that human. The log can show exact cross-profile mesh swaps even though profile+career matching appears correct.
- Other peers may see different colours if only one side has the human's synced cosmetic store, while every affected bot still points at the same owner peer.

### Diagnosis pattern
1. `ScoreboardHelper.get_grouped_topic_statistics` records `player:network_id()` as `peer_id` for every human and bot, and records `is_player_controlled` separately (`scoreboard_helper.lua:352,360,393-398`). For a bot, that peer is its network owner, not its cosmetic wearer.
2. If a resolver matches a bot's exact profile/career and returns its `peer_id`, a downstream per-peer human store aliases to the host. Multiple unrelated rows can therefore resolve to one peer without any career-only fallback.

### Fix template
- Treat score identity as a compound boundary: exact profile + exact career + `is_player_controlled == true` + complete peer/local-player tuple. Fail closed for bots and incomplete rows before consulting any human-only per-peer store.
- Apply the same exact profile+career requirement to live-human fallbacks; never make career optional and never use a peer-only fallback.
- A bot's skeleton mismatch must never invalidate state keyed to its human owner peer. Keep the cross-skeleton apply guard, but reserve store purging for a confirmed player-controlled wearer mismatch.
- Regression-fixture one human and two bots with different profile/career pairs but the same peer. Only the human may resolve.

### Related Issues / commits
- cosmetics_tweaker v0.9.95-dev (#513), pure resolver `_cos_score_identity.lua`, runtime check `cos_la_score_screen_apply_wired`.

## 39. Text caret geometry uses proxy font metrics

**First seen:** 2026-07-13 (gui_tweaker_dev issue #575; fixed v0.2.240-dev)
**Canonical Issue:** [#575](https://github.com/Ensrick/vermintide-2-tweaker/issues/575)
**Lives in:** custom text inputs/carets layered onto VMF or vanilla widgets, especially centered numeric fields.

### Symptoms
- The caret appears about one character left or right of the intended insertion point.
- A guessed pixel correction works for one value but fails for minus signs, decimals, proportional digits, UI scale, or resolution.
- Keyboard movement changes the logical index correctly while the drawn bar remains visually displaced.

### Diagnosis pattern
1. Compare the text style's material, `font_type`, size, alignment, and renderer scale with the measurement call. A material path is not a substitute for the font identity.
2. Trace the native text pass: `UIFontByResolution` resolves scaled material/size; `UIRenderer.text_size` returns width and glyph origin; centered alignment subtracts that origin.
3. Measure every prefix boundary. Character count or average glyph width cannot place clicks in proportional text.

### Fix template
- Use the exact rendered style with `UIFontByResolution(style)` and pass `style.font_type` to `UIRenderer.text_size`.
- Compute centered text-left as `box_x + (box_w - full_width) / 2 - origin_x`; caret X adds the measured prefix width.
- For mouse placement, choose the nearest boundary from measured widths of `""`, first character, through the full string. Keep logical edit/navigation/commit state independent from drawing geometry.
- Lock the pure geometry with proportional synthetic advances and source-gate every live presentation call site.

### Related Issues / commits
- gui_tweaker_dev v0.2.240-dev (#575), runtime `mod_tweaker_numeric_caret_geometry`, offline `test_mod_tweaker_numeric_editor.lua`.

## 40. Native cross-access item competes with variant owner

**First seen:** 2026-07-13 (WT/CWV issue #582)
**Canonical Issue:** [#582](https://github.com/Ensrick/vermintide-2-tweaker/issues/582)

When one mod exposes a donor's native item through `can_wield` while another owns a receiver-specific clone, the player sees duplicate-looking weapons but only the variant has the intended cosmetics, persistence, and routing. Pick one receiver owner. Remove the donor-native entry from every control/catalog surface, tombstone stale `can_wield` state, and reject invalid cached loadouts through vanilla fallback. Regression coverage must prove native exclusion and dedicated-variant registration/cosmetic parity for every intended receiver.

Related coverage: WT `issue582_native_dual_axes_cwv_ownership_boundary`; CWV `issue582_dual_axes_native_variant_ownership_boundary` and `dual_axes_cosmetic_family_parity`.

## 41. Persistent resource follows wielded instead of equipped slot

**First seen:** 2026-07-13 (WT issues #584 and #585)
**Canonical Issues:** [#584](https://github.com/Ensrick/vermintide-2-tweaker/issues/584), [#585](https://github.com/Ensrick/vermintide-2-tweaker/issues/585)

A career-owned resource extension outlives the weapon instance. Detecting only the wielded item stops passive recharge while melee is active and can leave a stale HUD bar after replacement. Use one owner-local planner that reads the owning equipped slot and selects exactly one action: recharge, neutralize stale state after removal, or no-op. Exclude native owners and test wielded/stowed parity, replacement, re-equip, repeated swaps, and bounded slot reads.

Related coverage: WT `issue584_moonfire_stowed_native_regen_contract`, `issue585_moonfire_energy_hud_loadout_lifecycle`, and `qa/lua/tests/test_wt_passive_charge.lua`.
## 42. Generated animation picks replace the receiver safety map instead of merging

**First seen:** 2026-07-14 (weapon_tweaker issue #290; fixed in source v0.12.230-dev)
**Canonical Issue:** [#290](https://github.com/Ensrick/vermintide-2-tweaker/issues/290)
**Lives in:** cross-character animation systems that combine a hand-authored receiver map with generated or user-baked event picks.

### Symptoms
- A foreign weapon equips in the correct stance, but most/all 3P attacks silently retain the prior pose.
- Inventory evidence proves the weapon was selected, while the later trace may belong to another weapon and cannot verify the report.
- A baked table looks populated, yet its keys are 1P `anim_event` names and the 3P body receives distinct `anim_event_3p` values.

### Fix template
- Derive the donor's effective body vocabulary as `anim_event_3p or anim_event` per action from source.
- Merge baked picks into the complete receiver safety map; never assign a partial generated table over it.
- Derive the receiver-native passthrough vocabulary from source and assert every effective donor event is either explicitly remapped or native.
- Arm bounded, weapon-identity-gated diagnostics for the next actual attack; selecting a weapon in inventory is not proof that the recorded attack used it.

### Related Issues / commits
- weapon_tweaker v0.12.230-dev (#290), runtime `issue290_billhook_kruber_effective_3p_complete`, diagnostic `[wt:290]`.

## 43. Durable owner customization is confused with ephemeral render state

**First seen:** 2026-07-13 (cosmetics_tweaker issue #574; fixed v0.9.92-dev through v0.9.94-dev)
**Canonical Issue:** [#574](https://github.com/Ensrick/vermintide-2-tweaker/issues/574)

A live material preview, durable owner preference, and remote peer render cache
have different identities and lifetimes. Saving a mutable preview on close can
commit canceled edits; keying only by weapon type merges inventory instances or
illusions; assuming one spawn callback reaches every surface leaves previews,
husks, swaps, or hot joins at vanilla state.

Use an explicit transaction: clone committed state into preview state, mark dirty
on edits, persist and emit only on Apply, make repeated Apply a no-op, and restore
the committed snapshot on close. Persist owner state by exact backend item plus
illusion. The wire payload must omit owner-local backend IDs and instead carry a
wearer, active slot, illusion context, and validated glow components. Receivers
cache by wearer and fail closed unless the spawned unit matches that context.

The durable commit must also be independent of render/network liveness. A valid
inventory Apply can carry an exact backend item and hand while `player_unit` is
temporarily absent during a keep or mission transition. Persist that exact owner
record first, then conditionally deliver it to the live model/peers; use bounded
lifecycle replay for unavailable consumers. Provider-owned exact instances that
are known but not yet injected into the backend mirror are deferred, not consumed
as a successful one-shot restore (#702).

Treat equipment creation, local wield, asynchronous hero preview, remote husk
wield, initial join, and hot join as separate render consumers. Reuse an
acknowledged post-ingame state pull for convergence, then retry only local paint
while equipment is unavailable. Bound retries by both cadence and deadline; do
not create a network retry loop. Do not synchronously purge peer caches on
`PlayerManager.remove_player`, which also fires during level transitions (bug
class 24).

Related coverage: Cosmetics runtime `glow_picker_apply_transaction_574` and
`glow_picker_render_fanout_574`; offline `test_cos_glow_lifecycle.lua`; tier-a
source invariants for exact identity, explicit Apply, acknowledged state pull,
and no-network-retry convergence.

For independent components, exact item persistence alone is insufficient. Each
preview adapter must prove the saved record belongs to the current item's hand
pool and that the unit it will paint is the authored target. In
`LootItemUnitPreviewer`, queued `spawn_data[i].unit_name` is stronger evidence
than runtime unit metadata; an unreadable `Unit.get_data("unit_name")` must fail
closed rather than authorize a paint. An independent row-2 owner also suppresses
whole-skin fallback paint on that component (#481).

## 44. Wire-safe substitute is mechanically incompatible

**First seen:** 2026-07-13 (CWV issue #296; fixed v0.1.400-dev)
**Canonical Issue:** [#296](https://github.com/Ensrick/vermintide-2-tweaker/issues/296)

A mod-only pickup can require wire protection without being cosmetically
equivalent to its vanilla substitute. Trace both the encode/decode path and the
substitute's interaction callbacks. If ammo kind, ownership, refill, or delete
semantics differ, treat it as a gameplay axis: keep the real key only under
positive peer parity and degrade safely while parity is unknown or mixed.

For thrown weapons, do not confuse the tiny recovery-pickup spawn weight with
ordinary map loot. Verify the generic ammo-refill path separately.

Related coverage: CWV `cwv_wire_safe_thrown_variant_installed` and offline
`test_cwv_javelin_pickup.lua`.

## 45. Literal `mod:dofile` helper omitted from the compiled resource package

**First seen:** 2026-07-14 (Weapons of Chaos v0.1.11-dev)
**Canonical Issue:** [#595](https://github.com/Ensrick/vermintide-2-tweaker/issues/595)
**Lives in:** any VMB mod that adds a Lua helper and loads it with a literal
`mod:dofile(...)` while its `.package` uses an explicit Lua file list.

### Symptoms
- Source and offline Lua tests pass because the helper exists in the checkout.
- The shipped game log reports `Resource not found: scripts/mods/<mod>/<helper>.lua`.
- `mod:dofile` returns nil through VMF's safe-call boundary; a later hook indexes
  the expected module table and crashes during an otherwise unrelated lifecycle
  event such as initial player spawn.

### Diagnosis pattern
1. Match the first resource error to a literal `mod:dofile` target.
2. Read the owning `resource_packages/<mod>/<mod>.package`; an explicit `lua =
   [...]` list that omits the new helper is the root cause.
3. Do not accept source-level unit coverage as bundle evidence. Build with
   VMBLauncher and Murmur-hash the resource path; the resulting hash must appear
   as a `.lua` entry in the built mod bundle.

### Fix template
- Add the helper path to the owning package, or use the mod-root wildcard when
  that mod intentionally compiles every module.
- Validate the returned module shape before registering consumers. Preserve
  unrelated vanilla behavior and fail closed for unsafe mod-owned identities.
- Keep `qa/check_dofile_package_coverage.ps1` in the Quick gate. It checks every
  literal dofile target in the canonical active-mod inventory for both source
  existence and package coverage.

### Related Issues / commits
- WOC v0.1.12-dev (#595); offline `test_woc_wire_policy.lua`; repository gate
  `check_dofile_package_coverage.ps1`.

## 46. Post-hook initializes state after vanilla already consumed it

**First seen:** 2026-07-14 (CIM issue #524; fixed v0.8.76-dev)
**Canonical Issue:** [#524](https://github.com/Ensrick/vermintide-2-tweaker/issues/524)
**Lives in:** lifecycle hooks where vanilla constructs a child page, queries a
backend list, or snapshots state inside `on_enter`.

### Symptoms
- Registration logs prove every mod definition exists, yet the initial page is
  missing every injected row with no Lua error.
- Closing/reopening or changing pages may alter the result because the mod's
  state becomes active only after the first query.
- Offline policy tests pass: the data transformation is correct, but it never
  ran at the consumer boundary that produced the visible page.

### Diagnosis pattern
1. Read the vanilla lifecycle function, not only the hooked helper. If it calls
   the consumer (for example `_change_recipe_page`) before returning, a
   `hook_safe` callback is too late to provide prerequisites for that call.
2. Compare timestamps: the visible window enter precedes the mod's activation
   or cache-build evidence, while producer registration already succeeded.
3. Distinguish state preparation from post-render observation. The former must
   precede `func`; widget dumps may remain after it.

### Fix template
- Replace the existing singleton `hook_safe` with one wrapping `mod:hook` on the
  same `(Class, method)` pair; do not add a second hook.
- Activate and build prerequisites before calling the original. Preserve every
  vanilla return with an explicit count, then run observation-only diagnostics
  after the original returns.
- Add ordering coverage that fails if activation/cache rebuild moves after the
  original call, plus a runtime assertion over the entire injected catalog.

### Related Issues / commits
- CIM v0.8.76-dev (#524); offline `test_cim_cwv_template_catalog.lua`; runtime
  `issue524_all_cwv_blacksmith_selectors`.

## 47. Custom GUI texture exists, but not in the drawing renderer

**First seen:** 2026-07-15 (CIM Athanor list, issues #617/#618; related preview
issue #481); prior related incident: Tweaker: GUI issue #528.
**Lives in:** any custom texture/material used by a vanilla view with multiple
renderers (`ui_renderer`, `ui_top_renderer`, HDR/store/forge renderers).

### Symptoms
- The texture is present in the bundle and may render on one screen, yet a
  different screen crashes in `ui_passes.lua:134` or
  `UIRenderer_draw_texture` because the renderer resolves a nil material.
- A resource-residency check passes. This does not prove that the particular
  `Gui` owned by the drawing renderer registered that material.
- Replacing the icon with a vanilla atlas key avoids the crash.

### Diagnosis pattern
1. Record the exact view, pass, and renderer that performed the failing draw.
2. Trace the renderer's material list at `UIRenderer.create`; do not infer it
   from another renderer in the same view.
3. Treat the closure as `(resource resident, material registered in this Gui,
   pass has a non-nil string)`. All three must be true before drawing.

### Fix template
- Centralize custom GUI material registration and track it per renderer
  instance, not globally.
- At widget construction, emit the custom key only after positive proof for
  the renderer that will draw it. Otherwise use a resident vanilla fallback or
  omit the optional pass.
- Add a static catalogue-to-renderer closure test and a runtime assertion over
  every live custom icon row. Never rely on `pcall` around the native draw.

**Related:** class 23 covers keep-only materials drawn mid-mission. This class
also occurs inside the keep when the material is registered in the wrong
renderer. Evidence: CIM log 2026-07-15 07:09:11, custom Dual Axes icon
`icon_wpn_axe_hatchet_t1_dual_cwv` in `HeroWindowWeaveForgeWeapons._draw`.

## 48. Preview presentation is reimplemented per screen

**First seen:** recurring weapon/cosmetic cluster; formalized 2026-07-15 from
issues #420, #481, #617.
**Lives in:** item appearance code consumed by inventory, customization,
Athanor, lobby, score, owner, bot, and husk surfaces.

### Symptoms
- A model, texture, transform, pose, glow, icon, or component name/description is correct in one preview but
  missing or stale in another.
- Fixes become a screen-by-screen game of whack-a-mole because each consumer
  reconstructs a partial item presentation.
- The same custom asset safely falls back in one view and crashes or renders
  vanilla in another.

### Fix template
- Resolve one immutable presentation descriptor from canonical item-instance
  identity. It includes component units, material/texture overrides,
  perspective transforms, pose, residency requirements, and a fail-closed
  substitute.
- Make every surface adapt that descriptor to its renderer/spawn API. A surface
  may not re-derive identity, illusion, or transform policy.
- Pair each returned preview unit with the exact recipe entry that spawned it.
  Do not infer ownership from a shared pivot, slot name, or unreadable runtime
  metadata; multiple previewers can legitimately reuse identical coordinates in
  separate viewport worlds (#481).
- Treat item-card text as component-owned presentation: a selected offhand or
  shield supplies its own name and description, while the primary supplies
  only its side of a composed title. Never retain primary flavor text after an
  independent component resolves (#641).
- Test the full acceptance matrix in `WEAPON_APPEARANCE_STANDARD.md` plus the
  Athanor and customization panes. Include initial open, re-open, transition,
  hot join, and one unmodified control.

**Related:** class 43 covers durable owner state versus ephemeral render state;
class 27 covers husk identity; issue #420 owns the shared library extraction.

## 49. Visual-only custom unit drops vanilla behavioral contracts

**First seen:** 2026-07-15 (Encarmine helmet, issue #612; verified fixed by
retaining the exact Laurel donor and overriding only per-instance textures).
**Lives in:** imported or rebuilt hats, outfits, weapons, and props that replace
a vanilla unit rather than only its textures/materials.

### Symptoms
- The mesh is visible, but a feather no longer jiggles, the whole cosmetic does
  not fade near the camera, or LOD/attachment behavior differs from vanilla.
- The custom FBX contains only static meshes while the donor unit contains an
  armature, skinned renderables, animation/state-machine data, or dynamic
  joints.
- Material replacement changes fade/dither behavior even when geometry is
  otherwise identical.

### Fix template
- Inventory the donor unit's nonvisual contract before importing: skeleton,
  state machine, skinned meshes, dynamic/physics nodes, LODs, fade-compatible
  shader/material parent, links, and attachment nodes.
- Prefer retaining the vanilla donor unit and replacing instance materials or
  textures. If geometry must change, use a rig-preserving pipeline and prove
  every contract item survived compilation.
- Regression-test structure offline; verify jiggle, near-camera fade, remote
  rendering, preview rendering, and transition respawn in game.

## 50. Texture conversion preserves haze outside intended alpha

**First seen:** 2026-07-15 (Encarmine plume, issue #612; verified fixed with
the donor alpha/material graph and semantic armor/plume slot resolution).
**Lives in:** PNG/DDS/texture conversion with cutout or translucent assets,
especially mipmapped DXT textures.

### Symptoms
- A feather or decal is surrounded by translucent tape/film.
- The visible feature is much darker/brighter than its donor even though the
  source PNG looks acceptable at full resolution.
- Gloss, alpha edge, or silhouette changes by distance as mips are selected.

### Fix template
- Gate assets with alpha histograms: background must be zero alpha; keep only a
  narrow anti-aliased edge; reject broad populations of very-low alpha pixels.
- Inspect generated mip alpha coverage and the compiled texture's cut-alpha
  policy. Full-resolution PNG inspection is insufficient.
- Compare luminance and packed material channels against the actual donor
  asset. Tune diffuse and gloss independently; do not brighten by filling the
  transparent sheet.
- Render the compiled asset at near/mid/far distance and against light/dark
  backgrounds before shipping.

## 51. Completed agent branch never reaches canonical master

**First confirmed:** 2026-07-15 (issue #528 cleanup at `d95399a`; umbrella
issue #625).
**Lives in:** parallel-agent work completed on `agent/*` without an explicit
integration, ship, and ancestry reconciliation step.

### Symptoms
- A completion message or branch commit exists, but `git merge-base
  --is-ancestor <commit> master` fails and canonical source still contains the
  old hooks.
- GitHub labels/comments say work shipped while the current master, Workshop
  manifest, or tester log cannot contain that source.
- Repeating the task appears necessary because the earlier implementation is
  stranded rather than disproven.

### Fix template
- For every agent handoff, record commit, issue, changed paths, QA evidence,
  version, manifest, and final disposition. Completion is not accepted until
  the commit is an ancestor of canonical master or explicitly marked
  superseded/obsolete.
- Reconcile with patch equivalence, current-source overlap, and issue intent;
  never bulk-merge stale mod versions.
- Ship only from canonical source, then verify the Workshop manifest and the
  tester's `[<mod>:LOAD]` version. Issue #625 owns the backlog reconciliation.

## 52. Text descriptor normalization trips binary deploy verification

**First confirmed:** 2026-07-16 (Weapon Tweaker Dev ship, issue #646).
**Lives in:** release/deploy tooling that compares VMB output with Steam's
local Workshop copy.

### Symptoms
- Every compiled `.mod_bundle` hash matches, but the lone `.mod` descriptor is
  larger in the Workshop folder and fails the final deploy gate.
- Byte inspection shows exactly one added carriage return before each newline;
  decoded descriptor text is otherwise identical.
- One bounded redeploy produces the same mismatch because Steam rewrites the
  descriptor representation again.

### Fix template
- Keep byte-exact SHA-256 comparison for `.mod_bundle` and every non-descriptor
  artifact.
- For the exact `.mod` extension only, normalize CRLF pairs to LF before the
  comparison. Preserve standalone carriage returns, encoding markers, and all
  other bytes so a real descriptor change still fails.
- Test equivalent LF/CRLF descriptors, changed text, standalone CR, and a
  bundle containing the same newline-only byte difference. Issue #646 owns the
  canonical `ship.ps1` implementation.

## 53. Shared launcher root crosses git worktrees

**First confirmed:** 2026-07-16 (Weapon Tweaker Dev ship, issue #647).
**Lives in:** release wrappers that invoke VMBLauncher while several git
worktrees share `%APPDATA%\VMBLauncher\settings.json`.

### Symptoms
- A ship banner and Workshop title name the new version, but a tester loads the
  preceding version after resubscribing.
- The command ran from an issue worktree while VMBLauncher's global
  `ProjectRoot` still named another checkout.
- Local post-ship checks can compare against the invoking checkout even though
  VMBLauncher built and uploaded files from the configured checkout.
- A clean-worktree ship builds/uploads successfully, then its GitHub-release
  phase fails because that phase hardcodes an ignored launcher path inside the
  invoking worktree instead of consuming the already-approved dependency.

### Fix template
- At the wrapper boundary, temporarily bind the launcher's ProjectRoot to the
  repository that owns the invoked ship script. Do not change VMB's build,
  deploy, or upload semantics.
- Before invoking the full pipeline, require the launcher-resolved mod folder,
  source `MOD_VERSION`, git commit, and `published_id` to match the invoking
  checkout. Abort before any build/deploy/upload action on a mismatch.
- Preserve the machine-global settings bytes and restore them in `finally` on
  success and failure. Hold a named OS mutex across binding, the launcher
  action, and restoration so concurrent ships cannot swap the root underneath
  each other.
- Resolve launcher bytes once through a shared approved-candidate policy, pass
  the exact path, provenance source, and approval anchor into every later
  phase, and revalidate that immutable snapshot before reading version
  metadata. Do not reread mutable global settings during the handoff. A direct
  sub-tool may perform the same bounded fallback, but an explicit unapproved
  path or source mismatch must fail closed.
- Test two distinct worktree roots, every identity field, action failure, mutex
  cleanup, byte-exact restoration, clean external dependency handoff, invalid
  explicit paths, and provenance mismatch. Issues #647 and #683 own the wrapper
  and cross-phase gates.

## 54. Late registry extension misses boot-time derived definitions

**First confirmed:** 2026-07-16 (Mission Select crash, issue #649).
**Lives in:** a runtime-extensible catalog whose dependent table is generated
once during boot, then consumed later without an exact-path capability check.

### Symptoms
- A screen works with vanilla careers but crashes immediately after another mod
  adds a career/profile entry.
- The fatal names a missing derived leaf rather than the visible menu data. In
  #649 it was `completed_career_levels,pusfume,military,cataclysm_3`.
- The live career exists, but the dependent definition has no row for it.

### Diagnosis pattern
1. Find the consumer's exact lookup path and the point where the parent catalog
   is extended.
2. Trace how the dependent registry is generated. Vanilla populates
   `completed_career_levels` by iterating the then-current `CareerSettings`
   [src: `statistics_definitions.lua:556-576`], while Mission Select later
   iterates all live `profile.careers` [src:
   `start_game_window_mission_selection_console.lua:503-524`].
3. Confirm the missing exact leaf in the crash locals; do not infer failure from
   the custom entry's presence alone.

### Fix template
- Guard the narrow consumer, not the shared database/lookup API. Delegate
  unchanged when every exact path exists.
- For a presentation-only enumeration, shallow-filter only entries lacking the
  complete derived capability, preserving source identity and all valid rows.
- Do not `pcall` or default arbitrary lookup failures globally. Add an offline
  identity/immutability test and an in-game regression check for the guarded
  consumer. GUT dev's `_gut_guard649_mission_completion.lua` is the reference.

## 55. Release-by-tag route failure is not release absence

**First confirmed:** 2026-07-16 (filtered WOC/GUT Dev release, issue #651).
**Lives in:** release tooling that uses a tag-route exit code as the complete
release-existence decision.

### Symptoms
- `GET /releases/tags/<exact-tag>` and `gh release view <tag>` return HTTP 503.
- `GET /releases?per_page=N` still returns that exact tag, its release ID, and
  all assets, including `manifest.json`.
- Source, bundle, local deploy, and Workshop hashes are current; only the
  filtered GitHub asset update aborts or is misclassified as a missing release.

### Fix template
- Try the canonical exact-tag route first. Confirm 404 and transient failures
  through a bounded number of list pages using a case-sensitive exact
  `tag_name`. Ambiguous matches or a full-page bound exhaustion are unavailable,
  never absent, so no release may be created.
- Download through resolved release-asset IDs. Replace only requested assets by
  exact asset ID and upload through the numeric release ID, with the merged
  manifest last. Do not reuse the failed tag route.
- Preserve staged bundle/provenance/hash checks before mutation. Test normal,
  404, transient fallback, exact match, pagination/exhaustion, ambiguity, asset
  selection, asset-ID download, and release-ID upload entirely offline.

## 56. Roster parity is observed after game-object replication starts

**First confirmed:** 2026-07-16 (Event Tweaker issue #430 hot-join residual).
**Lives in:** features that replicate package-owned units while peer capability
is inferred from `PlayerManager` or a mod handshake triggered by player creation.

### Symptoms
- Initial all-modded players run the feature, but a late peer without the mod
  hard-crashes while joining.
- A roster beacon eventually reports the incompatible peer, but only after the
  engine has started synchronizing existing game objects.
- Package preload at a mod-owned activation callback protects peers running the
  mod, not a peer that has no such callback.

### Diagnosis pattern
1. Trace the peer state machine, game-session admission, and roster insertion as
   separate boundaries. In VT2, `GameSession.add_peer` occurs at
   `peer_states.lua:393`, while `PlayerManager:add_remote_player` occurs at
   `:450`; the latter cannot authorize the former.
2. Identify the first package-owned game object and prove whether every joining
   peer has loaded its package before game-session admission.
3. Audit deactivation/stop contracts for every feature member. A missing general
   stop function means late teardown is not proof that all replicated units are
   gone.

### Fix template
- Prefer vanilla-resident units/templates so no peer capability is required.
- Otherwise enforce a session contract before `GameSession.add_peer`: reject or
  defer joins while unsafe objects may exist, and separately fail closed when a
  server-known peer is not yet represented in the roster.
- If neither pre-admission containment nor complete synchronous teardown is
  proven, keep the package-bearing feature inert. A warning after roster
  insertion is diagnostics, not crash safety.
- Test initial mixed parity, a peer already pending at activation, mid-session
  hot join, lock release, unknown network state, and unchanged vanilla
  non-joinability. Event Tweaker's `event_tweaker_curse_join_policy.lua` is the
  reference.

## 57. Successful one-shot weapon transform is reset by animation

**First confirmed:** Weapon Tweaker hold-pose work; generalized for Weapons of
Chaos issue #613 (2026-07-16).
**Lives in:** custom or cross-character weapon presentation that writes the
linked weapon node only at spawn.

### Symptoms
- The apply call and its `pcall` succeed, yet the grip, rotation, or scale soon
  returns to the native pose.
- A static preview can look correct while animated first/third-person gameplay
  is wrong.
- Repeating the same spawn hook does not prove what the renderer retained.

### Diagnosis pattern
1. Log numeric before, immediate-after, next-update, and target pose values;
   success-only logging is insufficient.
2. Verify the attachment target from source. VT2 links weapon node 0 in
   `attachment_node_linking.lua`; changing nodes without evidence is not a fix.
3. Exercise an animation before declaring retention. WT's empirical record is
   in `weapon_tweaker/OFFSETS.md`.

### Fix template
- Keep one canonical transform descriptor. Capture the linked baseline and
  construct the absolute baseline-plus-offset target through the shared weapon
  appearance helper.
- Weak-track only animated gameplay consumers (owner 1P/3P where applicable,
  bots, and husks), compare retained state, and reapply only on measured drift.
  Prune dead units; keep static previews one-shot and create no transform RPC.
- Yield to explicit live development-tuner ownership so two writers do not
  fight. Cover animation overwrite, all consumers, and quaternion sign
  equivalence offline. WOC 0.1.24-dev is the reference implementation.

## 58. Linked weapon transform reports partial setter success

**First confirmed:** Weapons of Chaos issue #613, WOC `0.1.24-dev`
(2026-07-17).
**Lives in:** custom weapon transforms applied to the target root after
`GearUtils.link_units`.

### Symptoms
- Immediate readback after an apparently successful transform retains rotation
  but position and scale remain native.
- Repeating the writes every update produces `drift-unrepaired`; this is not a
  later animation reset.
- A helper returns true because it ORs three setter results, masking the two
  channels that did not retain their values.

### Diagnosis pattern
1. Log every channel before, immediately after, and at the next update. In the
   #613 log, both owner perspectives and husks kept Z `0` / scale `1` while the
   quaternion reached the target.
2. Distinguish the game-owned attachment root from authored render children.
   One-handed gear links node `0` (`attachment_node_linking.lua:2726-2753`),
   but that proves attachment ownership, not that an imported unit accepts an
   authored geometry pose on the same node. Resolve a child only from observed
   unit-node identity; never guess an index.
3. Follow vanilla's complete-pose contract. `GearUtils.link_units` saves
   `Unit.local_pose` (`gear_utils.lua:300-305`) and
   `restore_scene_graph` restores it through one `Unit.set_local_pose`
   (`:321-327`).

### Fix template
- Compose rotation, position, and scale into one
  `Matrix4x4.from_quaternion_position_scale` and write the proven target node
  atomically through the shared WeaponAppearance helper. Leave attachment node
  `0` under GearUtils ownership when live readback proves that root rejects the
  complete pose; WOC issue #712 resolves its named `blightreaper` render child.
- Return success only when every requested channel succeeds. Preserve a
  per-channel/mode/node/error report for diagnostics; never OR setter results.
- Keep class 57's retained-state comparison for later animation drift. Test the
  atomic path, rejected attachment-root path, named-child path, and a fallback
  where one channel raises. WOC `0.1.29-dev` is the current reference.

**Refined 2026-07-18:** WOC `0.1.28-dev` live logs showed the atomic node-0
write itself returning false on owner 1P/3P and character previews while the
same units positively resolved their authored renderable as node `2`. This
supersedes the earlier assumption that vanilla's scene-graph restoration made
node 0 a universally writable authored-transform target.

## 59. Private/cross-career weapon template omits career ability actions

**First confirmed:** Weapons of Chaos Blightreaper and Weapon Tweaker
cross-character ports (2026-07-16).
**Lives in:** any private, cloned, or foreign weapon template usable by a career
whose activated ability declares `action_name`.

### Symptoms
- The career bar is charged and the ability works with another weapon, but the
  input silently does nothing while a particular weapon is wielded.
- Several otherwise unrelated weapons fail for the same career.
- Copying only `activated_ability[1]` appears to work until a career selects an
  alternate row (Waywatcher's piercing action is the current two-row case).
- Cross-mod startup reports `conflict:action_career_*` even though each
  provider selected the same canonical action name.

### Diagnosis pattern
1. Read `CharacterStateHelper._get_chain_action_data`; vanilla iterates
   `career_extension:ability_amount()` and checks every ability `action_name`
   against the currently wielded item template.
2. Enumerate `CareerSettings[career].activated_ability`, not a guessed list.
   Current weapon-bound coverage is ten actions across Ranger Veteran,
   Waywatcher (two), Bounty Hunter, Pyromancer, Grail Knight, Outcast Engineer,
   Sister of the Thorn, Warrior Priest, and Necromancer.
3. Verify each named `ActionTemplates` row exists and is present by identity on
   every enabled private/cross-career template. Ability-class careers do not
   need a fabricated weapon action.
4. At every deep-clone boundary, inspect the private claim metadata as well as
   `template.actions`. A deep clone can copy the donor's owner registry and
   canonical action rows by value, producing false ownership and new table
   identities even though the declared donor remains canonical.

### Fix template
- Use `tools/shared_lib/_lib_career_weapon_actions.lua`; collect every declared
  row and preserve existing donor rows by identity. Every provider claims the
  shared row through that library; releasing one provider removes an injected
  row only after the final claimant releases it and only when its value has not
  been replaced. A local “I inserted this” boolean is insufficient when WT,
  CWV, and WOC can consume the same template in different load orders.
- Reconcile actions at the same lifecycle boundary as availability. In
  particular, a deferred post-CWV `can_wield` pass must run the career-action
  pass too; otherwise a late-created provider item becomes selectable while
  its effective template still lacks the ability row.
- Provider mods reconcile their completed item catalog through the shared
  integration. Do not hand-copy `activated_ability[1]` in individual weapon
  constructors: that misses alternate rows and lets the next private template
  bypass the contract.
- Before the first claim on a declared private clone, call the shared
  `prepare_inherited_clone` boundary with an exact source token. It discards
  copied donor claims and restores only rows whose donor is still the exact
  canonical `ActionTemplates` value. Repeated preparation is a no-op, so a
  later foreign replacement remains a hard conflict instead of being clobbered.
- Missing career settings/action providers are integration failures: emit a
  bounded runtime error and fail the offline matrix. Never silently skip them.
- Test all ten current actions, the Waywatcher alternate, existing-row identity,
  missing providers, clone-claim contamination, repeated preparation, foreign
  replacement, setting reapply, and disable cleanup. Issue #661 owns the
  WT/CWV/WOC cross-provider regression.

## 60. Non-stacking aura drivers remove another source's buff

**First confirmed:** 2026-07-17 (Career Tweaker issue #663).
**Lives in:** repeated aura sources whose update/remove code searches the target
by `buff_to_add` template instead of retaining per-source ownership.

### Symptoms
- Two players with the same aura make one buff-bar entry flicker or repeatedly
  disappear and return.
- One source is inside range while another is outside, and the effect churns at
  the aura update frequency.
- A single source is stable, so solo testing misses the bug.

### Diagnosis pattern
1. Read the driver update and removal functions. Vanilla
   `activate_buff_on_distance`, `markus_knight_proximity_buff_update`, and
   `remove_aura_buff` resolve any matching target buff and never compare its
   `attacker_unit` (`buff_function_templates.lua:2759-2810, :3343-3395,
   :3153-3183`).
2. Confirm the add path is server-controlled and records the source. BuffSystem
   stores `attacker_unit` beside each server id (`buff_system.lua:262-270`).
3. Distinguish gameplay churn from a HUD-only merge problem by counting actual
   add/remove transitions; never log every update tick.

### Fix template
- Give every driver an explicit claim set keyed by target, and coordinate one
  aggregate non-stacking result per `(template, target)`.
- Add the server buff on the first claim, do nothing when intermediate claims
  enter or leave, and remove it only on the final release. Driver teardown
  releases only its own claims.
- Keep existing vanilla buff names and RPC formats. Do not make the effect stack
  merely to distinguish sources. Test two sources, one source leaving, the
  final source leaving, driver removal, and repeated idempotent updates. Career
  Tweaker `_crt_foot_knight.lua` is the reference implementation.

## 61. Peer-addressed appearance state survives a human career change

**First confirmed:** 2026-07-17 (Cosmetics Tweaker issue #698).
**Lives in:** material, mesh, glow, pose, or presentation caches addressed only
by network peer and replayed onto a newly spawned remote husk.

### Symptoms
- A remote player switches career without leaving the lobby and their new body
  receives armor, a hat, or another appearance choice from the prior career.
- The stale repaint can occur after the correct vanilla body has already spawned,
  making the failure look like a material race rather than an identity leak.
- A host-owned bot can make a peer-only fix worse because bots share their
  network owner's peer id.

### Diagnosis pattern
1. Treat `peer_id` as a transport address, not wearer identity. Compare the
   cached record's creation career with the live render unit's inventory
   `_career_name`; `RemotePlayer.career_name` resolves the synchronized
   profile/career tuple, while `SimpleHuskInventoryExtension.init` stamps the
   same career on the render-side inventory.
2. Audit every replay edge, not only the original apply: deferred sends,
   authoritative rebroadcast, pull-on-ready, hot join, transition reconcile,
   husk pre-spawn mesh substitution, and post-wield material paint.
3. Prove that a mismatched unit is the player-controlled human before purging.
   A bot mismatch is only an owner-peer alias and must not erase human state.

### Fix template
- Stamp every peer-store entry and required RPC payload with the exact wearer
  career; bump the RPC schema when introducing that required field so legacy
  unstamped records fail closed.
- Before a human husk wield/spawn, invalidate mismatched and unstamped entries.
  Require the same exact career at mesh substitution and material reconcile.
- Reject bots from consuming the human peer store and never let their career
  mismatch purge it. Test one human career swap, one same-career control, one
  shared-peer bot, transition, hot join, and missing legacy identity.
- Register career change as a canonical appearance replay edge. Cosmetics
  Tweaker `_cos_husk_identity.lua` and `test_cos_husk_identity.lua` are the
  reference policy and regression fixture.
## 62. Native DX12 fence timeout after a UI/focus transition

**First confirmed:** 2026-07-15 (Tweaker: GUI issue #630).
**Lives in:** native D3D12 end-of-frame synchronization after a mod UI pass;
the renderer-thread stall can occur without a Lua exception.

### Symptoms
- The game freezes after opening or changing a settings view, then crashifies
  after `WaitForSingleObject` exceeds 15 seconds.
- The dump resolves through `D3D12RenderDevice::end_frame` and
  `RI::wait_for_fence`; `Application::update` accounts for the same interval.
- Lua memory is healthy and the log has no Lua or missing-material exception.
- A window active/inactive transition may be the final observable engine edge,
  but timing alone does not prove that focus caused the stall.

### Diagnosis pattern
1. Preserve the matching console log and dump. Do not classify a native fence
   wait as Lua heap exhaustion, a missing GUI material, or a package-residency
   failure without those distinct signatures.
2. Establish ownership from source. For #630, Mod Tweaker borrows IngameUI's
   long-lived renderer and uses one `UIRenderer.begin_pass`/`end_pass`; WT's
   hold-pose tuner creates no preview world, unit, renderer, or package.
3. Add bounded edge evidence outside the pass: presentation entry/exit,
   renderer identity, selected tab, `Window.has_focus()`, and draw begin/end
   balance. A balanced Lua return before the dump points below the mod's pass;
   an unmatched begin identifies a mod lifecycle boundary.
4. Reproduce the same focus sequence in a vanilla view as a control. A shared
   signature shifts investigation toward the driver/engine path; a Mod Tweaker-
   only signature keeps the borrowed-pass owner in scope.

### Fix template
- Do not skip drawing while unfocused, recreate the borrowed renderer, or force
  a focus state based only on temporal correlation. Those changes mask evidence
  and can create a second renderer owner.
- Keep diagnostics automatic, issue-prefixed, edge-triggered, and hard-capped.
  Remove them when the issue closes.
- Change behavior only after the next trace identifies an imbalance or a
  source-backed engine contract. Cover balanced, unmatched, focus-edge, tab-
  edge, both-presentation, and output-bound behavior offline. GUT
  `_gut_dx12_fence630.lua` is the diagnostic reference.

## 63. Texture resource is resident but the spawned unit material is unresolved

**First confirmed:** 2026-07-18 (CWV issues #617 and #742).
**Lives in:** custom meshes painted through `Unit.set_texture_for_materials`
across preview worlds, owner units, or remote husks.

### Symptoms
- `Application.can_get("texture", path)` returns true for every authored texture,
  yet `Unit.set_texture_for_materials` access-violates at address `0x8`.
- The immediately preceding engine warning says it failed to look up a material
  in the spawned unit, followed by a custom texture path in the Script Error.
- One render surface works while a preview world, transition, or remote husk
  crashes because each owns a separate material-binding lifecycle.

### Diagnosis pattern
1. Separate texture-resource residency from unit-material binding. The former
   does not prove the latter and must never be used as the sole native-call gate.
2. Census the actual spawned unit with pcall-wrapped `Unit.num_meshes`,
   `Unit.mesh`, `Mesh.num_materials`, and `Mesh.material`. Treat an absent mesh,
   zero materials, a missing handle, or `#ID[00000000]` as unsafe.
3. Never use `Material.num_parameters`, `parameter_name`, or `parameter_type` as
   diagnostics; those have their own pcall-bypassing resource-manager fault.
4. Audit every caller of the shared painter. #742 occurred in
   `SimpleHuskInventoryExtension._wield_slot` after #617 had fixed only the
   `LootItemUnitPreviewer` parent-material binding.

### Fix template
- Require both resource proof and a real-material census immediately before the
  native write. Preview-only parent rebinding, when source-backed, happens before
  the census; world/husk paths must not blindly inherit that mutation.
- Fail closed for the entire unit, retain its donor appearance, and log one
  bounded reason. Do not partially paint earlier meshes or retry per frame.
- Keep package/RPC remediation separate. #491 fixes remote package collection;
  it does not prove a spawned material handle.
- Test one fully bound unit, zero/missing/null materials, a later mesh failing
  after an earlier valid mesh, throwing introspection, preview, remote husk,
  transition, hot join, and a mixed-mod fallback. CWV
  `_cwv_old_musket_preview.lua` is the reference policy.

## 64. Mod presence does not prove numeric NetworkLookup identity

**First confirmed:** 2026-07-18 (Career Tweaker issue #776; incomplete issue
#425 contract).
**Lives in:** gameplay features that send mod-registered names as numeric
`NetworkLookup.*` IDs through vanilla RPCs.

### Symptoms
- Every peer has the mod and answers the same presence/schema beacon, yet a
  vanilla RPC resolves the incoming integer to a different local template.
- A receiver may crash on a contract that the sender's real buff never violated.
  In #776, local ID 1574 resolved to timed
  `crt_questingknight_impetuous_as`, while positive host server IDs 12, 13,
  and 9 triggered `Cannot use duration for server controlled buffs!`.
- `ProcFunctions.add_buff` could not be the direct origin because it always
  transmits server ID 0 (`proc_functions.lua:1956-1972`).

### Diagnosis pattern
1. Record the numeric lookup ID, decoded local name, server-controlled ID, and
   sender peer from the receiver before vanilla mutation.
2. Compare BOTH lookup directions (`name -> number` and `number -> name`) on
   every peer. Same mod version, registered-name set, or RPC schema is not proof.
3. Trace the alleged producer's wire call. If its protocol cannot emit the
   observed field (as with positive IDs above), classify the event as a catalog
   collision rather than changing the innocent template to fit it.
4. Check the receiver's native contract. `BuffSystem._add_buff_helper_function`
   rejects duration on every sub-buff when `server_buff_id > 0`
   (`buff_system.lua:248-260`).

### Fix template
- Build a deterministic identity from every owned network name plus its ACTUAL
  live numeric assignment, validating forward and reverse maps. Exchange that
  compact identity on the mod's VMF channel and gate every custom emission on
  an exact match; missing/mismatched identity is immediately inert.
- Add an unconditional receiver floor that owns only locally resolved mod names.
  Drop mismatch/collision traffic before vanilla, preserve unrelated traffic
  unchanged, and bound diagnostics once per reason/template.
- Keep the hot-join sender filter: replay occurs before any peer ack can exist.
- Route legal timed effects through the native synced path appropriate to their
  authority. For CRT's owner+server Impetuous effects, use
  `BuffSyncType.LocalAndServer` (`buff_system.lua:803-812,849-879`; vanilla
  example `morris_buff_settings.lua:4618-4627`), with no unsafe fallback.
- Test shifted numeric assignments, missing identity, exact identity, unrelated
  names, observed collision IDs, positive-server-duration rejection, bounded
  logs, hot join, refresh, and expiry. CRT `_crt_wire_policy.lua` and
  `test_crt_wire_contract.lua` are the reference implementation.
