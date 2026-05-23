# Tweaker Mod Bug-Pattern Catalogue

Patterns mined from `memory/feedback_*.md` + `memory/reference_*.md` plus every `**/CHANGELOG.md` under `vermintide-2-tweaker/`. Each entry below has cost at least one shipped version in this repo. Patterns already covered by `lint-mod.ps1` (duplicate VMF hook registration, Lua forward-reference closures) are intentionally OMITTED.

---

## Category A — Statically Checkable

### A1. `mod:hook_safe` with callback signature including `func`

**Symptom:** `mod:hook_safe` callbacks receive `(self, ...)` — there is NO `func` arg. Writing `function(func, self, ...) ... end` shifts `self` into `func`, every arg by one. Body that calls `func(self, ...)` then calls the `self` userdata, crashing with `attempt to call ... (a userdata value)` or silently no-opping.

**Detection:** for each `mod:hook_safe\s*\(` block, parse the inner `function\s*\(([^)]*)\)` signature. If the first parameter name is `func`, `f`, or `orig`, flag it. Already partially implemented in `_tools/hook_audit.ps1`.

**Example bug:**
```lua
mod:hook_safe("PlayerProjectileUnitExtension", "init", function(func, self, ...)
    func(self, ...)   -- crashes: 'self' is now in func
end)
```

**Example fix:**
```lua
mod:hook_safe("PlayerProjectileUnitExtension", "init", function(self, ...)
    -- post-init logic
end)
```

**Memory citation:** [`feedback_vmf_hook_safe_no_chain.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vmf_hook_safe_no_chain.md). **Tool citation:** `_tools/hook_audit.ps1` already implements the inverse check (`hook` with body that ignores `func`).

**Recommended check severity:** error

---

### A2. Return-collapse in `mod:hook` wrapper

**Symptom:** Hooked function returns multiple values. Writing `return wrapper(func(self, ...))` collapses every return after the first into `wrapper`'s arg list. Downstream callers see nil where the second/third return should be. Example crash: `horde_spawner.lua:1060: 'for' limit must be a number`.

**Detection:** in any `mod:hook` body, regex for `return\s+[A-Za-z_][A-Za-z0-9_]*\s*\(\s*func\s*\(` — i.e. a single-call `return wrapper(func(...))` pattern. Then warn: confirm wrapped function returns exactly one value.

**Example bug:**
```lua
mod:hook("HordeSpawner", "compose_blob_horde_spawn_list", function(func, self, composition, ...)
    return _apply_breed_swap(func(self, composition, ...))   -- 2nd return dropped
end)
```

**Example fix:**
```lua
mod:hook("HordeSpawner", "compose_blob_horde_spawn_list", function(func, self, composition, ...)
    local spawn_list, num_to_spawn = func(self, composition, ...)
    return _apply_breed_swap(spawn_list), num_to_spawn
end)
```

**Memory citation:** [`feedback_hook_multi_return_collapse.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_hook_multi_return_collapse.md). **CHANGELOG citation:** `enemy_tweaker` v0.2.4.

**Recommended check severity:** warning

---

### A3. Missing `rawget` on strict-lookup table existence check

**Symptom:** `NetworkLookup.*` tables install a strict `__index` metatable at boot that errors on any unknown-key GET. Writing `if not nl_breeds[name] then nl_breeds[name] = ... end` crashes on the GET side because the key doesn't exist yet.

**Detection:** grep for `NetworkLookup\.\w+\[` or `ItemMasterList\[` (or any other table identified as strict-lookup) used as the LHS of a boolean test (`if not X[key]`, `if X[key] == nil`). Whitelist `rawget(X, key)`.

**Example bug:**
```lua
if not NetworkLookup.breeds[def.name] then
    NetworkLookup.breeds[def.name] = ...
end
```

**Example fix:**
```lua
if not rawget(NetworkLookup.breeds, def.name) then
    NetworkLookup.breeds[def.name] = ...
end
```

**Memory citation:** [`feedback_vt2_strict_lookup_rawget.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vt2_strict_lookup_rawget.md). **CHANGELOG citation:** `enemy_tweaker` v0.2.2/v0.2.3 → v0.2.4.

**Recommended check severity:** error

---

### A4. `Unit.node(unit, name)` without `Unit.has_node` guard

**Symptom:** Stingray's `Unit.node` errors with `[Script Error]: <node_name>` if the node is missing, AND the error BYPASSES `pcall`. Wrapping `pcall(Unit.node, unit, name)` does NOT prevent the engine-level fatal.

**Detection:** grep for `Unit\.node\s*\(` calls. For each, walk backward in the same function/block looking for `Unit\.has_node\s*\(\s*[^,]+,\s*['"]<same_name>['"]` or a same-line short-circuit (`Unit.has_node(unit, n) and Unit.node(unit, n)`). Flag any unguarded call. Also flag any `pcall(Unit.node` or `pcall(function() return Unit.node`.

**Example bug:**
```lua
local ok, node = pcall(Unit.node, unit, "j_lock")   -- pcall doesn't save you
if ok then ... end
```

**Example fix:**
```lua
if Unit.has_node(unit, "j_lock") then
    local node = Unit.node(unit, "j_lock")
    ...
end
```

**Memory citation:** [`feedback_vt2_unit_node_not_pcall_safe.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vt2_unit_node_not_pcall_safe.md). **CHANGELOG citation:** `character_weapon_variants` v0.1.290 → v0.1.291.

**Recommended check severity:** error

---

### A5. `Unit.actor(unit, i)` iterated 0-based

**Symptom:** `Unit.actor` is 1-indexed. Iterating `for i = 0, num_actors - 1` returns nil at index 0 and skips the last actor; the `if actor then` guard silently no-ops. Bug is invisible — no error, no actors touched.

**Detection:** regex `for\s+\w+\s*=\s*0\s*,\s*[A-Za-z_.]+(num_actors|Unit\.num_actors[^,]*)\s*-\s*1` (zero-based actor iteration). Flag any. Also flag the inverse `for i = 1, Unit.num_actors(u) - 1 do` (off-by-one — should be `1, n`, not `1, n-1`).

**Example bug:**
```lua
for i = 0, Unit.num_actors(unit) - 1 do
    local actor = Unit.actor(unit, i)
    if actor then Actor.set_collision_enabled(actor, false) end
end
```

**Example fix:**
```lua
for i = 1, Unit.num_actors(unit) do
    local actor = Unit.actor(unit, i)
    if actor then Actor.set_collision_enabled(actor, false) end
end
```

**Memory citation:** [`feedback_vt2_unit_actor_one_indexed.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vt2_unit_actor_one_indexed.md). **CHANGELOG citation:** `chaos_wastes_tweaker` v0.6.16 → v0.6.19.

**Recommended check severity:** error

---

### A6. `mod:hook*` targeting `HeroPreviewer` for keep-inventory previewer methods

**Symptom:** VT2's `foundation/scripts/util/class.lua` COPIES parent methods into child classes at boot, before any mod loads. `MenuWorldPreviewer = class(MenuWorldPreviewer, HeroPreviewer)` means a `mod:hook("HeroPreviewer", "equip_item", ...)` registration silently never fires on the keep inventory previewer instance (which is always `MenuWorldPreviewer`).

**Detection:** regex `mod:hook(_safe)?\s*\(\s*['"]HeroPreviewer['"]` — flag every match. The body should target `MenuWorldPreviewer` (or hook both as defense-in-depth). Same rule for any known base→derived pair: `PlayFabMirrorBase` → `PlayFabMirrorAdventure` / `PlayFabMirrorDedicated`.

**Example bug:**
```lua
mod:hook_safe("HeroPreviewer", "equip_item", function(self, item, slot, ...) ... end)
```

**Example fix:**
```lua
mod:hook_safe("MenuWorldPreviewer", "equip_item", function(self, item, slot, ...) ... end)
```

**Memory citation:** [`feedback_inventory_preview_hook_menuworldpreviewer.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_inventory_preview_hook_menuworldpreviewer.md), [`feedback_vt2_class_hook_derived.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vt2_class_hook_derived.md). **CHANGELOG citation:** `weapon_tweaker` v0.12.16 → v0.12.17, `cosmetics_tweaker` v0.7.99.

**Recommended check severity:** error

---

### A7. `mod:hook_safe` on `LootItemUnitPreviewer.spawn_units`

**Symptom:** Vanilla writes `self._spawned_units = units` AFTER `spawn_units` returns. A `hook_safe` post-callback fires BEFORE that assignment, so any logic reading `self._spawned_units` gets nil and silently bails.

**Detection:** regex `mod:hook_safe\s*\(\s*['"]LootItemUnitPreviewer['"]\s*,\s*['"]spawn_units['"]`. Must be `mod:hook` (full wrapper) instead.

**Example bug:**
```lua
mod:hook_safe("LootItemUnitPreviewer", "spawn_units", function(self, spawn_data)
    local units = self._spawned_units   -- nil
    ...
end)
```

**Example fix:**
```lua
mod:hook("LootItemUnitPreviewer", "spawn_units", function(func, self, spawn_data)
    local units = func(self, spawn_data)
    -- transform units
    return units
end)
```

**Memory citation:** [`feedback_loot_previewer_hook_not_safe.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_loot_previewer_hook_not_safe.md). **CHANGELOG citation:** `cosmetics_tweaker` (bret-thinning scale), `character_weapon_variants` v0.1.127.

**Recommended check severity:** error

---

### A8. `pl:player_unit()` colon-call on Player field

**Symptom:** `Player.player_unit` is a FIELD, not a method. Calling it as `pl:player_unit()` errors with `attempt to call method 'player_unit' (a userdata value)`.

**Detection:** regex `[A-Za-z_][A-Za-z0-9_]*\s*:\s*player_unit\s*\(`. Flag every match.

**Example bug:**
```lua
local pu = Managers.player:local_player():player_unit()
```

**Example fix:**
```lua
local pu = Managers.player:local_player().player_unit
```

**Memory citation:** [`feedback_vt2_player_unit_field.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vt2_player_unit_field.md). **CHANGELOG citation:** `cosmetics_tweaker` v0.8.7/v0.8.8.

**Recommended check severity:** error

---

### A9. `table.unpack` instead of `unpack` (Lua 5.1)

**Symptom:** VT2 runs Lua 5.1. `table.unpack` is a 5.2+ rename; calling it errors with `attempt to call field 'unpack' (a nil value)`.

**Detection:** regex `\btable\.unpack\s*\(`. Flag every match.

**Example bug:**
```lua
local a, b, c = table.unpack(args)
```

**Example fix:**
```lua
local a, b, c = unpack(args)
```

**Memory citation:** repo `CLAUDE.md` Lua Environment section. **CHANGELOG citation:** repo standards (no shipped incident; pre-emptive rule).

**Recommended check severity:** error

---

### A10. `mod:hook(_, "BackendUtils", "can_wield_item", ...)` (forbidden)

**Symptom:** `BackendUtils.can_wield_item` is documented as not hookable from Workshop mods. Modify `ItemMasterList[key].can_wield` directly instead.

**Detection:** regex `mod:hook(_safe)?\s*\(\s*[^,]+,\s*['"]can_wield_item['"]`. Flag every match.

**Memory citation:** repo `CLAUDE.md` Hooking section, line "Do NOT hook `BackendUtils.can_wield_item`". **CHANGELOG citation:** `weapon_tweaker` 2025 entry "Fixed: `BackendUtils.can_wield_item` hook error on every load/toggle".

**Recommended check severity:** error

---

### A11. CWV backend_id regex hardcoded to `_001$`

**Symptom:** `def.instances > 1` produces backend_ids `_001`, `_002`, ... A regex like `bid:match("^(cwv_.-)_001$")` silently returns nil for instance 2+; the previewer/transform binding skips, the variant displays textureless / un-scaled.

**Detection:** in `character_weapon_variants/` (or any file referencing `cwv_`), regex `backend_id\s*:\s*match\s*\(\s*"\^.*_001\$?"`. Recommend replacement with `_%d%d%d$` or `_%d+$`.

**Example bug:**
```lua
local matched = info.backend_id:match("^(cwv_.-)_001$")
```

**Example fix:**
```lua
local matched = info.backend_id:match("^(cwv_.-)_%d%d%d$")
```

**Memory citation:** [`feedback_cwv_resolve_preview_def_instance_regex.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_cwv_resolve_preview_def_instance_regex.md). **CHANGELOG citation:** `character_weapon_variants` v0.1.317.

**Recommended check severity:** error

---

### A12. `mod:network_send(..., "server", ...)` (silently dropped)

**Symptom:** VMF's `convert_names_to_numbers` accepts only `"all"`, `"others"`, `"local"`, or a literal peer_id. The string `"server"` is silently dropped (treated as a literal peer id that doesn't exist) — no error, no log, no wire activity.

**Detection:** regex `mod:network_send\s*\(\s*[^,]+,\s*['"](server|host|clients|server_peer)['"]`. Flag every match.

**Example bug:**
```lua
mod:network_send("my_rpc_request", "server", payload)
```

**Example fix:**
```lua
local host = Managers.state.network and Managers.state.network.server_peer_id
if host then
    mod:network_send("my_rpc_request", host, payload)
end
```

**Memory citation:** [`reference_vmf_network_send_recipients.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/reference_vmf_network_send_recipients.md). **CHANGELOG citation:** `cosmetics_tweaker` v0.8.67 → v0.9.0.15 (~8 hours debug).

**Recommended check severity:** error

---

### A13. `Get-Content -Raw` without `-Encoding UTF8` in PS 5.1 scripts

**Symptom:** PowerShell 5.1's `Get-Content -Raw` reads files using the system code page (Windows-1252 on en-US), silently mangling UTF-8 multi-byte sequences. `•` becomes `â€¢`, `—` becomes `â€"`, etc. Re-writing as UTF-8 cements the garbage.

**Detection:** scan `**/*.ps1` for `Get-Content\s+(-Raw\s+)?[^|]+` calls that don't include `-Encoding\s+UTF8` and where the target file is `.cfg`, `.lua`, `.md`, `.txt`, or `.json`. Recommend `[System.IO.File]::ReadAllText($p, [System.Text.Encoding]::UTF8)`.

**Example bug:**
```powershell
$cfgRaw = Get-Content -Raw $cfgPath
```

**Example fix:**
```powershell
$cfgRaw = [System.IO.File]::ReadAllText($cfgPath, [System.Text.Encoding]::UTF8)
```

**Memory citation:** [`feedback_ps5_getcontent_utf8.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_ps5_getcontent_utf8.md). **CHANGELOG citation:** `_upload_helper.ps1` (2026-05-14), `chaos_wastes_tweaker` Workshop description mangling.

**Recommended check severity:** warning

---

### A14. `New-Item -Force <file>` (truncates existing content)

**Symptom:** `New-Item -ItemType File -Force <path>` TRUNCATES an existing file's content. Easy to confuse with `mkdir -p` semantics.

**Detection:** regex `New-Item\s+(-ItemType\s+File\s+)?-Force` in `.ps1`. If the path doesn't end in `\` and isn't preceded by `-ItemType\s+Directory`, flag.

**Memory citation:** repo PowerShell harness rule (in conversation system prompt).

**Recommended check severity:** warning

---

### A15. Mutator template lifecycle hooked on `server_*_function` (dead field)

**Symptom:** `scripts/settings/mutators/mutator_templates.lua` wraps each `template.server_<name>_function` field into `template.server.<name>_function` at engine boot, BEFORE mods load. The original field name (`server_start_function`, etc.) still exists but is never read by the dispatcher (`mutator_handler.lua:680-682`). A `mod:hook(template, "server_start_function", ...)` registers cleanly, never fires.

**Detection:** regex `mod:hook(_safe)?\s*\(\s*[^,]+,\s*['"]server_(start|stop|update|player_disabled|player_hit|initialize)_function['"]`. Recommend `template.server.<name>_function` target.

**Example bug:**
```lua
mod:hook(MutatorTemplates.isha, "server_start_function", function(func, ctx, data) ... end)
```

**Example fix:**
```lua
mod:hook(MutatorTemplates.isha.server, "start_function", function(func, ctx, data) ... end)
```

**Memory citation:** [`feedback_vt2_mutator_template_server_wrap.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vt2_mutator_template_server_wrap.md). **CHANGELOG citation:** `chaos_wastes_tweaker` v0.7.66 (Isha mutator suppression, caught in pre-deploy QA).

**Recommended check severity:** error

---

### A16. `_localization.lua` key consumed by vanilla `Localize`

**Symptom:** Strings in a mod's `_localization.lua` are only reachable via `mod:localize(key)` — they're NOT injected into the global `Localize`. Setting `pickup.hud_description = "cwv_interaction_javelin"` makes vanilla `Localize` return `<cwv_interaction_javelin>` (missing-key placeholder).

**Detection:** harder. Heuristic: extract every key declared in `**/<mod>_localization.lua`. For each, grep the mod's `.lua` files for assignment patterns like `\.hud_description\s*=\s*['"]<key>['"]`, `\.display_name\s*=\s*['"]<key>['"]`, `\.popup_text\s*=\s*['"]<key>['"]` etc. that flow into vanilla `Localize`. Flag any mod_localization key used in those contexts unless the mod also hooks `_G.Localize` to handle it.

**Example bug:**
```lua
-- _localization.lua
return { cwv_interaction_javelin = { en = "Tuskgor Javelin" } }
-- character_weapon_variants.lua
Pickups.ammo.cwv_javelin.hud_description = "cwv_interaction_javelin"   -- shows <cwv_interaction_javelin>
```

**Example fix:** hook `_G.Localize` to return the string explicitly. See memory citation.

**Memory citation:** [`feedback_vmf_mod_localization_not_global.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vmf_mod_localization_not_global.md). **CHANGELOG citation:** `character_weapon_variants` v0.1.190 → v0.1.199 (Tuskgor Javelin pickup popup).

**Recommended check severity:** warning (heuristic — false positives expected)

---

### A17. Localize-hook description string with unescaped `%`

**Symptom:** `Localize` hook returning a boon/talent/property description string. The result is downstream-formatted via `string.format(fmt, unpack(description_values))` in `UIUtils.format_localized_description`. A literal `%` becomes invalid format syntax; VMF substitutes `[Invalid String Format]`.

**Detection:** for any `mod:hook\s*\(\s*_G\s*,\s*['"]Localize['"]` body, scan returned string literals (`return\s+['"][^'"]*%[^'"]*['"]`) for unescaped `%` not followed by `%`, `d`, `s`, `f`, `i`, `x`, `q`, `g`, `.`, or another format directive. Warn.

**Example bug:**
```lua
mod:hook(_G, "Localize", function(func, key)
    if key == "deus_reckless_swings_desc" then
        return "+25% damage"   -- invalid format
    end
    return func(key)
end)
```

**Example fix:**
```lua
return "+25%% damage"
```

**Memory citation:** [`feedback_vt2_localize_string_format_pipeline.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vt2_localize_string_format_pipeline.md). **CHANGELOG citation:** `chaos_wastes_tweaker` v0.5.2-dev (Khaine's Fury description).

**Recommended check severity:** warning

---

### A18. Shared options-table reference across VMF dropdowns

**Symptom:** VMF's `localize_dropdown_data` MUTATES each `option.text` in place. Two dropdown widgets sharing the same options table reference → second pass `Localize`s the already-localized string → `<key>` brackets → cascade `<<key>>`, `<<<key>>>`, etc.

**Detection:** in any `_data.lua`, find every `options\s*=\s*([A-Za-z_][A-Za-z0-9_]*)` (identifier assignment, not inline literal). If the same identifier appears as `options =` on two or more widgets, flag.

**Example bug:**
```lua
local _MIMIC_OPTIONS = { { text = "off", value = "off" }, ... }
{ ..., options = _MIMIC_OPTIONS },
{ ..., options = _MIMIC_OPTIONS },   -- second dropdown gets <<off>>
```

**Example fix:**
```lua
local function _mimic_options() return { { text = "off", value = "off" }, ... } end
{ ..., options = _mimic_options() },
{ ..., options = _mimic_options() },
```

**Memory citation:** [`feedback_vmf_dropdown_options_mutated.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vmf_dropdown_options_mutated.md). **CHANGELOG citation:** `enemy_tweaker` v0.4.0 → v0.4.2.

**Recommended check severity:** error

---

### A19. Duplicate VMF widget `setting_id`

**Symptom:** VMF rejects duplicate `setting_id` values in the options tree and refuses to register the mod's options at all — the ENTIRE settings page disappears.

**Detection:** in every `_data.lua`, collect all `setting_id\s*=\s*['"]([^'"]+)['"]` matches. Flag duplicates.

**Memory citation:** [`reference_vmf_widget_id_unique.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/reference_vmf_widget_id_unique.md). **CHANGELOG citation:** `chaos_wastes_tweaker` v0.7.26-test.

**Recommended check severity:** error

---

### A20. Top-level chunk >200 locals (Lua 5.1 / LuaJIT cap)

**Symptom:** Compile error `main function has more than 200 local variables`. The compiler reports the line of the 201st declaration, not the root cause. Cited example was at line 8654.

**Detection:** for each `.lua` file in `scripts/mods/<mod>/`, count top-level `local\s+\w+` and `local\s+function\s+\w+` declarations NOT inside any function or `do ... end` scope. Warn at >150, error at >195.

**Example fix:** wrap helper groups in `do ... end` scopes — locals release at the `end`.

**Memory citation:** [`feedback_vt2_lua_200_locals.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vt2_lua_200_locals.md). **CHANGELOG citation:** `character_weapon_variants` v0.1.304.

**Recommended check severity:** warning

---

### A21. Storing raw `Quaternion` / `Vector3` in long-lived table

**Symptom:** Stingray's `Quaternion`, `Vector3`, `Matrix4x4` are stack-allocated temporaries valid only within the current frame. Storing the raw value in a Lua global, table field, or upvalue makes it stale by the next frame.

**Detection:** harder — true static check needs flow analysis. Heuristic: regex `_G\.\w+\s*=\s*(Quaternion|Vector3|Matrix4x4)\.` or `\w+\.\w+\s*=\s*(Quaternion|Vector3|Matrix4x4)\.[a-z_]+\s*\(` (assignment of a fresh Q/V/M to a table field — excluding the matching `Box` wrappers). Warn.

**Example bug:**
```lua
_G.MY_ROT = Quaternion.axis_angle(Vector3(1,1,-1), -math.pi/2)
```

**Example fix:**
```lua
_G.MY_ROT = QuaternionBox(Quaternion.axis_angle(Vector3(1,1,-1), -math.pi/2))
-- later: local rot = _G.MY_ROT:unbox()
```

**Memory citation:** [`feedback_vt2_quaternion_vector3_box_for_storage.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vt2_quaternion_vector3_box_for_storage.md). **CHANGELOG citation:** `character_weapon_variants` v0.1.297 → v0.1.298.

**Recommended check severity:** warning

---

### A22. `MOD_VERSION` suffix containing change descriptor

**Symptom:** Workshop title gets `v<MOD_VERSION>` appended on upload. Suffixes like `-revert`, `-hotfix`, `-la-icons`, `-botgate`, `-mirror`, `-glowbid` are user-flagged anti-patterns. Only release-track suffixes allowed: `alpha`, `beta`, `dev`, `rc`.

**Detection:** in every `scripts/mods/<mod>/<mod>.lua`, regex `MOD_VERSION\s*=\s*['"]\d+\.\d+\.\d+(\.\d+)?-(\w+)['"]`. If captured suffix is NOT in `{alpha, beta, dev, rc, prerelease}`, flag.

**Example bug:**
```lua
local MOD_VERSION = "0.9.9.1-revert"
```

**Example fix:**
```lua
local MOD_VERSION = "0.9.9.1-alpha"
```

**Memory citation:** [`feedback_mod_version_format.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_mod_version_format.md). **CHANGELOG citation:** Burned 2026-05-22 (cosmetics_tweaker `0.9.9.1-revert`).

**Recommended check severity:** warning

---

### A23. Missing `name` field on injected `special_events` entry

**Symptom:** `BackendInterfaceLiveEventsPlayfab.get_special_events` hook returning entries without `name` → dialogue_system.lua:200 crashes `table index is nil` on the keep load. Crashes at startup (not just on missions).

**Detection:** in `event_tweaker/` or any file hooking `get_special_events` / `get_active_events`, find table-literal entries returned from those hooks. If an entry has `weekly_event` or `mutators` but no `name = ...` field, flag.

**Example bug:**
```lua
{ weekly_event = "append", mutators = { "geheimnisnacht_2021" } }   -- crashes
```

**Example fix:**
```lua
{ name = "geheimnisnacht_2021", weekly_event = "append", mutators = {...} }
```

**Memory citation:** [`feedback_special_events_name_required.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_special_events_name_required.md). **CHANGELOG citation:** `event_tweaker` v0.2.0 → v0.2.1.

**Recommended check severity:** error

---

### A24. `mod:get` for a setting that must be host-authoritative

**Symptom:** ct (and similar) sync host settings to clients via `effective_setting(key)`. Reading the same key via raw `mod:get(key)` in a host-authoritative code path (curse disable, boon pool, registration order, mission availability) causes per-peer divergence — crashes from index mismatches, wrong curse text, etc.

**Detection:** harder. Heuristic: for each mod that defines an `effective_setting(...)` helper, build the set of keys it covers (often a whitelist or "everything except a small per-peer list"). Then grep the mod for `mod:get\(["']([^"']+)["']\)` and flag any key in the host-authoritative set.

**Example bug:**
```lua
if mod:get("disable_curse_khorne") then ... end   -- per-peer, host wanted authoritative
```

**Example fix:**
```lua
if effective_setting("disable_curse_khorne") then ... end
```

**Memory citation:** [`feedback_vt2_gated_registration_diverges.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vt2_gated_registration_diverges.md). **CHANGELOG citation:** `chaos_wastes_tweaker` v0.7.54, v0.7.55, v0.7.49.

**Recommended check severity:** warning (project-specific; needs allow-list of synced keys)

---

### A25. CWV variant `entry.name` / `entry.key` clobbered (drop inherited)

**Symptom:** `entry.name = def.item_key` after `table.clone(base, true)` breaks downstream `ItemMasterList[item.name]` lookups (cwv items are MIL-registered, not in IML). Crash on equip: `backend_utils.lua: attempt to index local 'item_data' (a nil value)`.

**Detection:** in `character_weapon_variants/` files, find any assignment `entry\.(name|key)\s*=` after a `table.clone(base` clone. Recommended pattern is to keep inherited name and set `entry.cwv_variant = true`.

**Memory citation:** [`feedback_cwv_clone_name_clobber.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_cwv_clone_name_clobber.md). **CHANGELOG citation:** historical CWV registration crashes.

**Recommended check severity:** error

---

### A26. CWV ammo-weapon variant skin missing field mirror

**Symptom:** `BackendUtils.get_item_units` unconditionally overwrites `ammo_unit`, `ammo_unit_3p`, `projectile_units_template`, `pickup_template_name`, `link_pickup_template_name` from the skin template. If the variant's WeaponSkins entry doesn't mirror these from the base, the field goes nil → previewer crash on string concat, throw crash, pickup crash.

**Detection:** in `_register_variant_skins`-style functions, find the skin-table entry build. If the variant's base is detected (heuristic: base entry has `is_ammo_weapon == true`), require all five fields to be explicitly set (or fall through with `or base.<field>`).

**Memory citation:** [`feedback_cwv_ammo_unit_required.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_cwv_ammo_unit_required.md). **CHANGELOG citation:** `character_weapon_variants` v0.1.64, v0.1.184.

**Recommended check severity:** warning (project-specific, needs a manifest of cwv ammo-weapon base entries)

---

### A27. Empty `mod:hook_safe(...)` callback signature

**Symptom:** Common typo: writing `mod:hook_safe(Class, method, function() ... end)` (no params). For most hooks the body needs at least `self`. Body either crashes on `self` reference or silently no-ops.

**Detection:** regex `mod:hook_safe\s*\([^,]+,\s*[^,]+,\s*function\s*\(\s*\)`. Flag every match.

**Recommended check severity:** warning

---

### A28. CHANGELOG entry missing version bump (no MOD_VERSION change in same commit)

**Symptom:** User reports rely on the version string echoed in chat to confirm the deploy landed. Same version = no visible confirmation = wasted testing time.

**Detection:** workflow-level. Compare `git diff HEAD~1 HEAD` for `<mod>/scripts/mods/<mod>/<mod>.lua`; if the diff touches code but does NOT touch the `MOD_VERSION = "..."` line, flag pre-build.

**Memory citation:** [`feedback_version_bump.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_version_bump.md), [`feedback_pre_deploy_checklist.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_pre_deploy_checklist.md).

**Recommended check severity:** warning

---

## Category B — Manual Review Only

### B1. Husk-extension class pair coverage

**Symptom:** Hooking `SimpleInventoryExtension.wield` silently does nothing for remote players' wield events on the local viewer's machine — that path goes through `SimpleHuskInventoryExtension.wield`. Same for many other player-unit extensions. Husk classes are independent root classes, not subclasses.

**Why static check is infeasible:** the lint would need to maintain a manifest of every known self-owned/husk extension class pair (`scripts/network/unit_extension_templates.lua`) and cross-check that any hook on a self-owned extension also has a parallel hook (or a shared global-function hook) on the husk twin. Doable but requires curated input list and an "intentional skip" annotation.

**Memory citation:** [`feedback_vt2_husk_extension_class_pair.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vt2_husk_extension_class_pair.md). **CHANGELOG citation:** `weapon_tweaker` v0.12.35 → v0.12.37.

---

### B2. LA custom-mesh / kind="unit" pipeline omissions

**Symptom:** Loremaster's Armoury `kind="unit"` skin entries require LA's full `swap_units_new` bookkeeping plus mutating `WeaponSkins.skins[skin][hand]`. Skipping any step → magenta mesh or `NetworkLookup.inventory_packages` crash.

**Why static check is infeasible:** failure mode depends on runtime LA tick ordering, peer-state sync, and the visual output (magenta vs. correct material). No source pattern reliably distinguishes correct from buggy registration without runtime state.

**Memory citation:** [`feedback_la_custom_mesh_unsupported.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_la_custom_mesh_unsupported.md), [`reference_la_kind_unit_pipeline.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/reference_la_kind_unit_pipeline.md), [`reference_la_offhand_paint.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/reference_la_offhand_paint.md), [`reference_la_custom_mesh_pattern.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/reference_la_custom_mesh_pattern.md). **CHANGELOG citation:** `cosmetics_tweaker` v0.8.11 → v0.8.13, v0.8.27 → v0.8.48 (~20 versions).

---

### B3. Gated network-replicated registration ordering

**Symptom:** Any mod-load registration into `_G.BuffTemplates`, `DeusPowerUpBuffTemplates`, `DeusPowerUpTemplates`, `NetworkLookup.*`, or `LevelSettings` gated by per-user toggle → different sequential indices across peers → `rpc_add_buff` crash with "Table buff_templates does not contain key: N".

**Why static check is infeasible:** detection requires understanding control flow — *which* registration writes are inside an `if mod:get(...)` block AND *which* keys are network-replicated. Possible with curated knowledge of which tables matter (NetworkLookup.*, BuffTemplates, LevelSettings, DeusPowerUp*) and a conservative "any registration to these tables inside a toggle conditional" pass, but high false-positive rate without flow analysis.

**Memory citation:** [`feedback_vt2_gated_registration_diverges.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vt2_gated_registration_diverges.md). **CHANGELOG citation:** `chaos_wastes_tweaker` v0.7.59 → v0.7.62 (3 sub-systems migrated to unconditional sorted pre-registration).

---

### B4. Runtime CW boon injection not dual-registered

**Symptom:** New CW boons must be written to BOTH `DeusPowerUpBuffTemplates` AND `_G.BuffTemplates`. Vanilla merges them at boot via DLCUtils; mods load AFTER the merge. Single-table write → first roll crashes `buff_extension.lua:177`.

**Why static check is infeasible:** detection would need to identify all "runtime boon injection" sites and confirm both writes are present. Source patterns are mod-specific (helper functions in ct, indirect through dispatcher) and indistinguishable from harmless template reads without semantic analysis.

**Memory citation:** [`feedback_vt2_dormant_buff_template_dual_register.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vt2_dormant_buff_template_dual_register.md). **CHANGELOG citation:** `chaos_wastes_tweaker` v0.7.31 → v0.7.32.

---

### B5. Cross-character LA cosmetic patched onto wrong skeleton

**Symptom:** LA hat geometry has attachment-node IDs that exist only on the source character's rig. Patching a Kerillian Maiden Guard hat onto a Sienna bot crashes at `Unit.node(unit, "j_spine1")` (the node ID isn't in Sienna's skeleton table). Bug surfaces when bots replace disconnected players in CW deus runs.

**Why static check is infeasible:** the bug is runtime data corruption (stale cross-character cache) — no source pattern reveals it. Defensive check needs runtime data (incoming wearer career vs cached LA item's character).

**Memory citation:** `cosmetics_tweaker` v0.9.8.5 CHANGELOG entry. **CHANGELOG citation:** `cosmetics_tweaker` v0.9.8.3 → v0.9.8.6 (4 versions).

---

### B6. Cross-character unit package not pre-loaded

**Symptom:** Vanilla's package loader queues inventory packages off the equipped item's `right_hand_unit` / `left_hand_unit`. Any cross-character unit reference (pickup unit from another character's kit, projectile unit, per-perspective 3P override) is NOT auto-queued. `World.spawn_unit` on the unloaded path crashes hard (sometimes returns nil and wrecks unrelated state).

**Why static check is infeasible:** the lint would need a database of which unit paths belong to which character's package, and full understanding of which fields participate in package resolution. Possible but requires curated input + a per-variant audit table.

**Memory citation:** [`feedback_cwv_cross_character_unit_packages.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_cwv_cross_character_unit_packages.md). **CHANGELOG citation:** `character_weapon_variants` v0.1.118 (Tuskgor Javelin), `weapon_tweaker` v0.12.5 (Brace-Repeater post-migration).

---

### B7. Animation remap target outside target template's closed vocabulary

**Symptom:** Cross-character anim remap target picked from `Unit.has_animation_event TRUE` results or the skeleton-events probe — but the target wield-SM template doesn't author that event, so no clip plays. Visual: "previous-weapon idle stance + missing fire/wield animation" (NOT a T-pose).

**Why static check is infeasible:** the lint would need to parse every weapon template's `anim_event` field across the entire `Vermintide-2-Source-Code/scripts/settings/equipment/weapon_templates/` decompile, build the per-template authored vocabulary, then check that every entry in a remap table targets one of those events. Doable but ambitious; also covered by [`character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md`](../../character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md).

**Memory citation:** [`feedback_anim_closed_vocabulary.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_anim_closed_vocabulary.md), [`feedback_animation_remap_rules.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_animation_remap_rules.md). **CHANGELOG citation:** `weapon_tweaker` v0.9.81 → v0.9.96 (wasted versions), `character_weapon_variants` v0.1.158 → v0.1.193.

---

### B8. RPC payload >500 chars (VMF `network_send` silent drop)

**Symptom:** VMF JSON-packs all `mod:network_send` args into a single string parameter. Stingray hard-caps that string at 500 chars. Payload over the cap fires `Failed to pack parameter 3, too many characters` INSIDE VMF's safe-hook wrapper — never crashes, never logs to chat, broadcast silently no-ops.

**Why static check is infeasible:** can't determine runtime payload size from source. A weak heuristic — flag `network_send` calls where any arg is a `table.concat`, JSON encoding, or a known-large table — would have high false positives. Better caught at runtime via a wrapper.

**Memory citation:** [`reference_vmf_rpc_string_cap.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/reference_vmf_rpc_string_cap.md). **CHANGELOG citation:** `chaos_wastes_tweaker` v0.7.55 → v0.7.58 (3 versions silently broken).

---

### B9. Property-value invention (no source-grounded number)

**Symptom:** CHANGELOG / tooltip / comment claims invented mechanic terms (`max_amount`, "stacks compound to 21%") that don't match the actual vanilla buff template or game flow.

**Why static check is infeasible:** the lint would need to grep VT2 decompiled source for every numeric claim in CHANGELOG.md. Pure content-review task.

**Memory citation:** [`feedback_no_invented_vt2_internals.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_no_invented_vt2_internals.md), [`feedback_vt2_breakpoints_no_guess.md`](../../../.claude/projects/C--Users-danjo-source-repos/memory/feedback_vt2_breakpoints_no_guess.md). **CHANGELOG citation:** `chaos_wastes_tweaker` v0.7.7-alpha.

---

## Recommended Implementation Priority (by historical incident count)

Top 5 Category A patterns to wire first, ranked by independent shipped-version incidents:

1. **A6 (HeroPreviewer → MenuWorldPreviewer)** — at least 4 documented incidents across weapon_tweaker, cosmetics_tweaker, and character_weapon_variants. Each cost a full version.
2. **A1 (`mod:hook_safe` with `func` first param)** + duplicate already-covered rule — exactly mirrors the duplicate-hook silent-drop class; multiple cwv and cosmetics_tweaker incidents.
3. **A7 (`LootItemUnitPreviewer.spawn_units` hook_safe)** — bit cosmetics_tweaker AND character_weapon_variants (twice).
4. **A11 (CWV `_001$` regex)** — bit every multi-instance variant in v0.1.317 onward.
5. **A18 (shared options table)** — instantly catches a class of bug that survives until the user reports `<<<key>>>` brackets in chat.

Lower priority but high signal: **A8, A9, A12, A14, A15, A19, A23, A27** are pure-syntax checks with zero false positives.
