# Loading LA Assets Without LA Being Enabled — Feasibility Audit

Read-only research dated 2026-05-19, in response to: friend has LA subscribed but
disabled in the launcher; cosmetics_tweaker's `_la_bridge.lua` therefore stays
dormant on her PC and host LA broadcasts paint nothing locally. Can
`la_prefix_patch` provide a stand-in so cosmetics_tweaker still works?

Sources walked: `mod_manager.lua` (vanilla), `package_manager.lua` (vanilla),
VMF `vmf_mod_manager.lua` / `vmf_package_manager.lua` bytecode token dumps,
`Loremasters-Armoury.lua` / `.mod` / `funcs.lua` / `skin_list.lua`,
`la_prefix_patch.lua` / `.mod`, `cosmetics_tweaker/_la_bridge.lua`,
`cosmetics_tweaker/LA_SYNC_MODEL.md`, `LYNDSEY_LA_DIAGNOSIS.md`, plus the
memory files cited in the task brief.

---

## TL;DR

`la_prefix_patch` **cannot** load LA's textures/units without LA itself being
enabled. The blocker is engine-level mod-scoped resource handles, not Lua
scoping. The shippable path is graceful degradation in cosmetics_tweaker:
package LA's `SKIN_LIST` keys and texture references **as static data inside
la_prefix_patch**, so the bridge can validate peer broadcasts and emit
clear "LA assets unavailable" UX without crashing, even when LA-the-mod
is dormant. Visual painting still requires the host's chosen LA texture
to be in the receiver's engine resource registry — which requires LA enabled.

---

## Verdicts on Q1-Q4 (read-only, with cites)

### Q1: `Managers.package:load("resource_packages/Loremasters-Armoury/Loremasters-Armoury", "la_prefix_patch", nil, true, true)` from la_prefix_patch?

**Verdict: NO. Will fatal with `Resource '#ID[...]' not found`.**

Cites:
- `foundation/scripts/managers/package/package_manager.lua:81` (and again at
  `:94`, `:109`, `:139` — every path through `PackageManager.load` /
  `force_load` / `force_load_queued_package`) calls
  `Application.resource_package(package_name)`.
- `feedback_vt2_no_custom_package_paths.md` documents the registry split:
  `Application.resource_package` resolves into the **global** registry, which
  only contains paths bundled into vanilla `bundle/` OR loaded via
  `Mod.resource_package(<some_handle>, name)` at mod-script init time.
- `mod_manager.lua:421` shows the only loader of mod packages:
  `Mod.resource_package(mod.handle, package_name)`. `mod.handle` is the
  per-mod handle returned by `Mod.start_scan` / `Mod.mods()`
  (`mod_manager.lua:143`). That handle is scoped to a single mod's bundle.

LA's bundle (`3ac73385950a26ea.mod_bundle`, 240 MB on disk in
`workshop/content/552500/2789506353/`) contains LA's units/textures.
la_prefix_patch's bundle (`209fb8c3c0a8c3a4.mod_bundle` et al.) contains only
la_prefix_patch's lua, per its `resource_packages/la_prefix_patch/la_prefix_patch.package`:

```
mod     = [ "la_prefix_patch" ]
package = [ "resource_packages/la_prefix_patch/la_prefix_patch" ]
lua     = [ "scripts/mods/la_prefix_patch/*" ]
```

Even if la_prefix_patch's `.mod` `packages = {...}` list named LA's package
path, the engine would route it through
`Mod.resource_package(la_prefix_patch.handle, "resource_packages/Loremasters-Armoury/Loremasters-Armoury")`
(`mod_manager.lua:421`), which looks for that path **inside la_prefix_patch's
own bundle**, finds nothing, and the resulting `resource_handle` either
fails the subsequent `ResourcePackage.load` synchronously or never resolves
the units inside.

When LA is disabled in the launcher, `_load_mod` skips LA entirely
(`mod_manager.lua:354-357` — `while mod and not mod.enabled do index = index +
1`), so LA's bundle never gets `_load_package`'d, and LA's textures/units
never enter the global registry. There is no Lua API that can opt a
disabled mod's bundle into the global registry from another mod.

(`DEVELOPMENT.md § Force-load only paths in inventory_package_list.lua` adds the related
constraint that even VANILLA `Managers.package:load(<path>)` requires the
path to appear in `scripts/network_lookup/inventory_package_list.lua` —
LA's resource paths definitely do not appear there.)

### Q2: How is `LA.SKIN_LIST` exposed?

**Verdict: Pure data. Trivially copyable, but requires shipping ~1765 lines
verbatim in la_prefix_patch's source tree.**

`skin_list.lua:1-3` assigns directly to the LA mod table:

```lua
local mod = get_mod("Loremasters-Armoury")
mod.SKIN_LIST = { ... }
```

The contents are pure-data tables — strings, numbers, nested tables; no
closures, no `Vector3()` calls, no userdata. Reviewed all 1765 lines: every
entry is a flat record like `{ kind = "texture", swap_skin = nil, textures =
{...}, swap_hand = "...", skip_meshes = {...}, icons = {...} }`. Safe to
serialize-and-copy.

But there's a key sub-question: cosmetics_tweaker's bridge consumes
`LA.SKIN_LIST` for two things:
1. **Validation/enumeration** of which armoury_keys exist + their `swap_hand`,
   `new_units`, `icons` (so the bridge can clone IML entries, register
   variants, etc.). This works entirely against static data.
2. **`textures` array** for the live paint path — `_paint_offhand_textures_locally`
   calls `Unit.set_texture_for_materials(unit, slot, path)` where `path` is
   a string from `variant.textures[1..3]`. This call's success depends on
   the texture being in the engine's resource registry. Without LA loaded,
   `Application.can_get("texture", path)` will return false (and the bridge
   already gates on it — `_la_bridge.lua:1240`). So painting silently no-ops
   on Lyndsey's PC even with static data.

### Q3: Can `mod:dofile` load files from another mod's directory?

**Verdict: NO. `mod:dofile` is scoped to the calling mod's compiled lua glob.**

Direct VMF source isn't available in cleartext (Workshop ships LuaJIT
bytecode in `vmf_out/FA3F694D1916D375.lua`), but the token dump of
`vmf_mod_manager.lua` shows `safe_call_dofile` is the wrapping primitive
and resolves via the same engine `Mod.*` family that scopes by mod handle.
The compile-time evidence is direct: la_prefix_patch's
`la_prefix_patch.package` declares `lua = [ "scripts/mods/la_prefix_patch/*" ]`
(no LA glob). The compiler only bundles files under that glob into
la_prefix_patch's `.mod_bundle`. A call from la_prefix_patch's main script
saying `mod:dofile("scripts/mods/Loremasters-Armoury/skin_list")` would
search la_prefix_patch's bundle for a file at that path; it isn't there;
the call returns nil (or errors).

**Workaround:** la_prefix_patch's `.package` can extend its `lua = [...]`
glob to include a *copy* of LA's `skin_list.lua` placed under
`la_prefix_patch/scripts/mods/Loremasters-Armoury/` (or any path inside its
own tree). The vmb compiler will pick it up. Then `mod:dofile` resolves
locally. **But this is just shipping a copy** — same as Q2's recommendation.

### Q4: Can we shim `get_mod("Loremasters-Armoury")`?

**Verdict: YES for the bridge's `get_mod` lookup. NO for fully replacing
LA-the-mod at engine level.**

Two routes:

a) **Hook `_G.get_mod`** like la_prefix_patch already does for `Material-Hijack`
   (`la_prefix_patch.lua:67-86`):

   ```lua
   _G.get_mod = function(name)
       if name == "Loremasters-Armoury" then
           local original = _orig_get_mod("Loremasters-Armoury")
           if original then return original end
           return _LA_SHIM   -- our fabricated stub
       end
       return _orig_get_mod(name)
   end
   ```

   Where `_LA_SHIM` is a synthesized table exposing `.SKIN_LIST`,
   `.level_queue = {}`, `.preview_queue = {}`, `.armory_preview_queue = {}`,
   `.SKIN_CHANGED = {}`, plus stub functions for `apply_new_skin_from_texture`,
   `re_apply_illusion`, `render_marker`, etc. Anything the bridge calls.

b) **Call `new_mod("Loremasters-Armoury", {...})`** ourselves from
   la_prefix_patch. Possible but messy — fights VMF's "duplicate_mod_name"
   guard (token visible in `FA3F694D1916D375.lua` strings: `duplicate_mod_name`
   error key). VMF rejects a second registration of the same name. And it
   wouldn't load LA's actual `mod_script` either (we don't have its handle).
   The hook route (a) is strictly cleaner.

The shim only solves the **`get_mod` returns non-nil** problem. It does NOT
solve **textures-aren't-in-engine-memory** (Q1).

---

## Recommended Implementation Path

Two-layer approach:

### Layer 1: Extract LA's data tables into la_prefix_patch as static modules

Treat la_prefix_patch as the "always-on" twin of LA. Even though it can't
load LA's binary assets, it can hold the *catalog* — every armoury_key, its
`swap_hand`, `new_units`, `textures` paths, `icons` map, `kind`. This is
~50-80 KB of pure-data Lua.

File layout:

```
la_prefix_patch/
  scripts/mods/la_prefix_patch/
    la_prefix_patch.lua           (existing)
    _la_data/
      skin_list.lua               (copy of LA's, edited to set
                                    mod.SKIN_LIST -> M.SKIN_LIST and
                                    return M.SKIN_LIST)
      string_dict.lua             (if cosmetics_tweaker ever needs it;
                                    today it doesn't)
```

Procedure to bring it in:

1. Verbatim-copy `Loremasters-Armoury/scripts/mods/Loremasters-Armoury/skin_list.lua`
   into `la_prefix_patch/scripts/mods/la_prefix_patch/_la_data/skin_list.lua`.
2. Replace `local mod = get_mod("Loremasters-Armoury")` and
   `mod.SKIN_LIST = {...}` with `local M = {}; M.SKIN_LIST = {...}; return M`.
3. In `la_prefix_patch.lua`, do `local LA_DATA = mod:dofile("scripts/mods/la_prefix_patch/_la_data/skin_list")`.
4. Track LA's repo for monthly drift. The data churns infrequently (LA hasn't
   had a Workshop bump since 12/9/2024 per Lyndsey diagnosis) so this is
   low-maintenance.

### Layer 2: `get_mod` shim with capability flag

In `la_prefix_patch.lua`, extend the existing `get_mod("Material-Hijack")`
alias to also handle `Loremasters-Armoury`:

```lua
local _LA_SHIM   -- forward-declared so we can build it after data loads
local function build_la_shim()
    return {
        -- Capability flag for callers that want to branch
        _is_la_prefix_patch_shim = true,
        _real_la_enabled = false,

        -- The data the bridge actually needs
        SKIN_LIST = LA_DATA.SKIN_LIST,

        -- Empty mutable tables the bridge writes into; safe to ignore.
        level_queue         = {},
        preview_queue       = {},
        armory_preview_queue = {},
        SKIN_CHANGED        = {},

        -- Stubs that no-op safely. The bridge already pcall-wraps
        -- apply_new_skin_from_texture (`_la_bridge.lua:735`).
        apply_new_skin_from_texture = function() return end,
        re_apply_illusion           = function() return end,
        render_marker               = function() return end,
        update                      = function() return end,
    }
end

_G.get_mod = function(name)
    if name == "Loremasters-Armoury" then
        local real = _orig_get_mod("Loremasters-Armoury")
        if real then
            -- LA actually loaded — return the real thing and flag the shim
            -- as inactive. cosmetics_tweaker can keep its existing path.
            return real
        end
        if not _LA_SHIM then _LA_SHIM = build_la_shim() end
        return _LA_SHIM
    end
    -- (existing Material-Hijack branch)
    return _orig_get_mod(name)
end
```

### Layer 3: cosmetics_tweaker bridge adjustment

cosmetics_tweaker's `_la_bridge.lua` already has rich nil-guards (every code
path checks `if not LA then return` or `if not LA.SKIN_LIST then return`).
With the shim returning a non-nil `LA` whose `SKIN_LIST` is populated, the
bridge will:

- Successfully `register_all()` — IML entries get cloned, MIL learns them,
  inventory shows the LA "items".
- Successfully resolve peer broadcasts (`_la_equips_by_peer` lookups hit).
- Detect `_is_la_prefix_patch_shim == true` and skip the visual paint when
  it knows the texture won't bind. Add one branch in
  `_paint_offhand_textures_locally`:

  ```lua
  local function _is_shim_only()
      local L = la()
      return L and L._is_la_prefix_patch_shim and not L._real_la_enabled
  end

  if _is_shim_only() then
      -- Inventory/icon ops still work (handled by IML mirror). Skip per-
      -- unit material paint — the texture paths from LA's bundle aren't
      -- in this peer's engine registry, so Unit.set_texture_for_materials
      -- would either no-op or warn.
      if M.trace then mod:info("[LA bridge] shim-only mode; skipping paint for %s", armoury_key) end
      return false
  end
  ```

- For the husk-paint replay path (peer-broadcast incoming), the receiver
  also early-exits, so vanilla mesh + vanilla texture stays. No crash.

What the user (e.g. Lyndsey) sees with this stack:

| Capability | LA enabled | la_prefix_patch shim only |
|---|---|---|
| LA hat/shield variants in inventory | Yes | Yes (IML clones registered) |
| Selection persists across sessions | Yes | Yes (VMF settings unaffected) |
| Local viewer sees correct LA paint on own player | Yes | No — vanilla texture |
| Local viewer sees correct LA paint on remote peers | Yes | No — vanilla texture |
| Crashes / chat errors | None | None (graceful) |
| Bridge logs `dependency missing: Loremaster's Armoury` | No | No (shim returns non-nil) |
| New log: `[LA bridge] running against la_prefix_patch shim; visuals unavailable, validation+inventory only` | n/a | Yes, once at register-all |

The friend can pick LA items in the menu, they'll persist, and the host's
broadcasts will reach her without errors. Visuals are vanilla — but the
crash/dormancy class of bug is gone.

---

## Code Patch Sketches

### Patch A: `la_prefix_patch/la_prefix_patch.package`

```
mod = [
    "la_prefix_patch"
]

package = [
    "resource_packages/la_prefix_patch/la_prefix_patch"
]

lua = [
    "scripts/mods/la_prefix_patch/*",
    "scripts/mods/la_prefix_patch/_la_data/*"
]
```

### Patch B: `la_prefix_patch/scripts/mods/la_prefix_patch/_la_data/skin_list.lua`

Mechanical: copy from
`Loremasters-Armoury/scripts/mods/Loremasters-Armoury/skin_list.lua`
verbatim, then replace the opening 2 lines and the final EOF:

```lua
-- AUTO-MIRROR of LA's skin_list.lua.
-- Source: github.com/dalokraff/Loremasters-Armoury — keep in lockstep.
-- Last sync: 2026-05-19 from LA Workshop ID 2789506353 (LA hasn't updated since 2024-12-09).
local M = {}

M.SKIN_LIST = {
    Kruber_Grail_Knight_Bastonne02 = {
        kind = "texture",
        ...
    },
    ...  -- 1765 lines of pure data
}

return M
```

### Patch C: `la_prefix_patch/scripts/mods/la_prefix_patch/la_prefix_patch.lua`

Add near the top (after MOD_VERSION echo, before the existing VMFMod patch):

```lua
-- Shim Loremaster's Armoury so cosmetics_tweaker's _la_bridge works even
-- when LA itself is subscribed-but-disabled. The shim exposes LA.SKIN_LIST
-- (catalog data; copied at compile time) plus the queue tables the bridge
-- writes into. apply_new_skin_from_texture is a safe no-op — LA's textures
-- aren't in the engine resource registry without LA loaded, so visual
-- painting can't work. cosmetics_tweaker's bridge detects shim-mode via
-- `_is_la_prefix_patch_shim` and degrades gracefully (inventory + validation
-- only; vanilla mesh/textures render).
local LA_DATA = mod:dofile("scripts/mods/la_prefix_patch/_la_data/skin_list")

local _LA_SHIM
local function build_la_shim()
    return {
        _is_la_prefix_patch_shim = true,
        _real_la_enabled         = false,
        SKIN_LIST                = LA_DATA.SKIN_LIST,
        level_queue              = {},
        preview_queue            = {},
        armory_preview_queue     = {},
        SKIN_CHANGED             = {},
        apply_new_skin_from_texture = function() return end,
        re_apply_illusion           = function() return end,
        render_marker               = function() return end,
        update                      = function() return end,
    }
end
```

Then extend the existing `_G.get_mod` patch (currently scoped to
`"Material-Hijack"`) to also handle `"Loremasters-Armoury"`:

```lua
_G.get_mod = function(name)
    if name == "Loremasters-Armoury" then
        local real = _orig_get_mod("Loremasters-Armoury")
        if real then
            -- LA actually loaded; nothing to shim. The bridge will use the
            -- real LA's tables/functions as before.
            if _LA_SHIM then _LA_SHIM._real_la_enabled = true end
            return real
        end
        if not _LA_SHIM then
            _LA_SHIM = build_la_shim()
            mod:info("Loremaster's Armoury not loaded — la_prefix_patch SKIN_LIST shim active (1765 entries).")
        end
        return _LA_SHIM
    end
    if name == "Material-Hijack" then
        -- (existing branch — unchanged)
    end
    return _orig_get_mod(name)
end
```

### Patch D: `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua`

Single helper + early-exit branch in `_paint_offhand_textures_locally`:

```lua
local function _is_shim_only()
    local L = la()
    return L and L._is_la_prefix_patch_shim and not L._real_la_enabled
end

local function _paint_offhand_textures_locally(unit, variant, armoury_key, context)
    if not unit or type(unit) ~= "userdata" then return false end
    if not Unit.alive(unit) then return false end

    -- la_prefix_patch shim is supplying SKIN_LIST data but LA's textures
    -- aren't in this peer's engine resource registry. Skip the per-unit
    -- paint; vanilla material stays, no crash, inventory mirror intact.
    if _is_shim_only() then
        if M.trace then
            mod:info("[LA bridge] shim-only: skipping %s paint (context=%s)",
                tostring(armoury_key), tostring(context))
        end
        return false
    end

    -- (rest of function unchanged)
```

Optionally also add a one-time chat notice on `register_all`:

```lua
if _is_shim_only() then
    mod:echo("[Cosmetics Tweaker] LA disabled — running against la_prefix_patch shim. LA items are selectable, but vanilla textures render. Enable Loremaster's Armoury for full visuals.")
end
```

### Patch E (optional, smallest delta): if shipping the data copy is rejected

If the user prefers NOT to bundle LA's data verbatim (workshop hygiene,
attribution, file size), fall back to the **shim with empty SKIN_LIST**.
The bridge then keeps the `dependency missing` dormant path, but at least
`_la_equips_by_peer` writes don't fail with key errors, and the
`[LA bridge] miss: variant ... not in LA.SKIN_LIST` log line becomes the
explicit "go enable LA" indicator. Minimal patch:

- Patches A and B above are skipped.
- Patch C's `build_la_shim` returns `SKIN_LIST = {}`.
- Patch D's `_is_shim_only` branch can additionally surface a chat hint
  the first time the bridge sees a peer broadcast for an unknown key.

This is strictly worse than the full data-copy path for the friend's UX,
but it solves the crash/spam class of bugs with one new file and 30 lines
of la_prefix_patch.

---

## What this cannot fix (be explicit)

- **Cross-peer visual consistency** when one peer has LA enabled and another
  doesn't: physically impossible. The texture pixels live in LA's bundle,
  which isn't in the disabled-peer's engine. No Lua-level shim can paint
  them. Best graceful state is "disabled peer sees vanilla; enabled peers
  see LA mesh — desync is silent and confined to that one viewer".
- **kind="unit" mesh swap on the shim peer**: same root cause. The custom
  FBX is in LA's bundle. Vanilla mesh renders instead. LA_SYNC_MODEL.md
  table row "kind='unit' mesh swap on a remote (non-LA) viewer" already
  enshrines this.
- **Auto-enabling LA in the user's launcher**: VMF/engine don't expose a
  Lua API to flip `Application.user_setting("mods")[i].enabled = true` and
  re-scan. Even if it did, the engine's mod scan runs once at boot; flipping
  the flag at runtime wouldn't materialize the bundle into memory.

---

## File-path summary

- `C:\Users\danjo\source\repos\vermintide-2-tweaker\la_prefix_patch\la_prefix_patch.mod`
- `C:\Users\danjo\source\repos\vermintide-2-tweaker\la_prefix_patch\resource_packages\la_prefix_patch\la_prefix_patch.package`
- `C:\Users\danjo\source\repos\vermintide-2-tweaker\la_prefix_patch\scripts\mods\la_prefix_patch\la_prefix_patch.lua`
- `C:\Users\danjo\source\repos\vermintide-2-tweaker\cosmetics_tweaker\scripts\mods\cosmetics_tweaker\_la_bridge.lua`
- `C:\Users\danjo\source\repos\Loremasters-Armoury\Loremasters-Armoury.mod`
- `C:\Users\danjo\source\repos\Loremasters-Armoury\scripts\mods\Loremasters-Armoury\Loremasters-Armoury.lua`
- `C:\Users\danjo\source\repos\Loremasters-Armoury\scripts\mods\Loremasters-Armoury\skin_list.lua`
- `C:\Users\danjo\source\repos\Loremasters-Armoury\scripts\mods\Loremasters-Armoury\utils\funcs.lua`
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\managers\mod\mod_manager.lua` (key cites: 143, 354-357, 410-428)
- `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\foundation\scripts\managers\package\package_manager.lua` (key cite: 81, 94, 109)
- `C:\Users\danjo\source\repos\vermintide-2-tweaker\cosmetics_tweaker\LA_SYNC_MODEL.md`
- `C:\Users\danjo\source\repos\vermintide-2-tweaker\cosmetics_tweaker\LYNDSEY_LA_DIAGNOSIS.md`
