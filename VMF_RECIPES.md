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
local host = Managers.state.network and Managers.state.network.server_peer_id
if not host then
    -- Level transition window; server_peer_id is transiently nil during
    -- host migration / pre-join / loading. Defer or pending-queue the send.
    return
end
mod:network_send("my_rpc_request", host, payload)
```

`server_peer_id` is set on `Managers.state.network` after session-join
handshake completes. Always guard.

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
