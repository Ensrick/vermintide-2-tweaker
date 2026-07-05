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

Full mechanic + naming convention: `VMF_RECIPES.md § 12`. Optional bt runtime safety net: `bt:safe_event_register(em, target, event_name, name_or_fn)` (auto-adapts function values + logs `[ALERT]` with caller stack frame). Adapter is the safety net, NOT the primary fix.

### Related Issues / commits
- gt v0.2.61 (`_gt_lobby_motd.lua` — first fix; on_player_joined_party MOTD)
- gt v0.2.62 (`_gt_lobby_session_ignore.lua` — second fix; session-ignore join filter)
- gt v0.2.63 (`_gt_lobby_slot_reservations.lua` — third fix; slot reservation enforcement)
- gt v0.2.64 (additional sites missed in .61-.63 — final pass)
- bt v0.1.10-alpha — `mod.safe_event_register` runtime adapter landed
- New static check: `qa/check_event_register_signature.ps1` (Quick mode)

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
