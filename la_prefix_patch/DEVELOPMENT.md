# LA Prefix Patch — Development Notes

Architecture, prototype-patching pattern, and Quiet Mode rationale for
`la_prefix_patch`. Read alongside `CHANGELOG.md` (history),
`LOAD_LA_WITHOUT_LA.md` (feasibility audit for the LA-disabled-but-subscribed
scenario), and `REGRESSION_CHECKLIST.md` (pre-release gates).

---

## Overview

- **Mod:** `la_prefix_patch` (Workshop ID `3721067411`, **private**,
  never set public).
- **Repo path:** `C:/Users/danjo/source/repos/vermintide-2-tweaker/la_prefix_patch/`

### What it does

1. **Patches `VMFMod.hook` / `hook_safe` / `hook_origin`** on the
   prototype so that any second call from a mod whose name is
   `"Loremasters-Armoury"` to the same `(obj, method)` pair is silently
   dropped before VMF can emit its `Attempting to rehook active hook [...]`
   warning. First registration wins, which is the correct semantics for
   all three of LA's dupes (`LevelEndView.start`,
   `LevelTransitionHandler.load_current_level`,
   `LocalizationManager._base_lookup`).
2. **Quiet Mode toggles (v0.3.0-dev, 2026-05-08):** two opt-in VMF
   checkboxes (`suppress_la_quest_markers`,
   `suppress_la_notifications`) under the `la_quiet_group`.
   - **Markers** — monkey-patches `LA.render_marker` in
     `mod.on_all_mods_loaded` (single chokepoint for board, scrolls,
     pickups, sword shrine). Toggle is read live inside the closure so
     flipping takes effect on the next frame without re-patching.
     Idempotency-guarded with `LA._la_prefix_patch_marker_wrapped`.
   - **Notifications** — la_prefix_patch loads first → its
     `NewsFeedUI.init` hook is innermost → by the time it runs, LA has
     already inserted `LA_unread_letter` into `NewsFeedTemplates` (LA
     does its insert *before* calling `func`). Post-wraps
     `condition_func` to short-circuit when the toggle is on.
     Idempotency-guarded with `tmpl._la_prefix_patch_notif_wrapped`.

### Why it exists

- LA author dalokraff has been silent for 3 years (last commit late
  2022) — upstream PR is not viable.
- The three rehook warnings echo to chat at startup, burying user's
  own mod-version banners.
- Side-loading the patch ships **zero LA code** — no MIT attribution
  burden, no Jaffawer asset-licensing question.

### Load-order requirement

Must sit **ABOVE** `Loremaster's Armoury` in the launcher list,
otherwise the prototype patch isn't installed before LA's mod_script
runs and registers its hooks. The launcher load order is set per user;
document this in any redistribution.

### Related (forward-looking)

Future Cosmetics Tweaker integration of LA's cosmetics (visual library
only, drop quest/letter/news/achievements) is contingent on this mod
being installed first — it provides the "LA loaded but quiet"
foundation. See `LOAD_LA_WITHOUT_LA.md` for the feasibility audit
covering the LA-disabled-but-subscribed scenario.

### `get_mod("Material-Hijack")` alias (v0.3.1-dev)

Wraps `_G.get_mod` so callers looking up `"Material-Hijack"`
transparently fall back to the `material_hijack_patched` instance when
the original is disabled. Belt-and-braces — a 2026-05-19 audit
confirmed LA itself has zero `get_mod("Material-Hijack")` calls; LA's
coupling to MH is purely data-driven (`mat_to_use` / `mat_slots` data
nodes on LA units). Safety: only intercepts the exact string
`"Material-Hijack"`. All other `get_mod` calls pass through unchanged.
If `material_hijack_patched` itself isn't enabled, the original lookup
proceeds normally.

---

## Prototype patching pattern

### The timing problem

VMF's `new_mod(name, resources)` (vmf_mod_manager.lua:95-132) does
**all four** steps inside one call:

1. Create the VMFMod instance via `create_mod(name)`.
2. Load `mod_localization`.
3. Load `mod_data`.
4. Load `mod_script` ← the script's top-level code runs HERE, before
   `new_mod()` returns.

This means: when **mod A**'s script runs, only mods that already
finished `new_mod()` exist. Any mod registered later (including those
listed below A in the launcher) is invisible — `get_mod("MyTarget")`
returns `nil`.

### What doesn't work

```lua
local target = get_mod("Loremasters-Armoury")
if target then
    target.hook = wrap(target.hook)  -- never reached when load order has us above target
end
```

### What works: patch the VMFMod prototype

```lua
local TARGET_NAME = "Loremasters-Armoury"

local function wrap(orig_method)
    if type(orig_method) ~= "function" then return orig_method end
    return function(self, obj, method, handler)
        if self.get_name and self:get_name() == TARGET_NAME then
            -- per-target filtering / dupe detection / etc.
        end
        return orig_method(self, obj, method, handler)
    end
end

if rawget(_G, "VMFMod") then
    VMFMod.hook        = wrap(VMFMod.hook)
    VMFMod.hook_safe   = wrap(VMFMod.hook_safe)
    VMFMod.hook_origin = wrap(VMFMod.hook_origin)
end
```

`VMFMod` is a global. Modifying it propagates to all future and
existing instances via Lua's `__index` lookup (VMF instances are plain
tables with VMFMod as their `__index`, not method-copied subclasses —
different from VT2's `class()` pattern that *does* copy at definition
time).

### Load-order requirement

The patcher mod must sit **above** the target in the launcher list, so
its script runs **before** the target's `new_mod()` is called.
Patching after the fact does nothing for hooks already registered.

### Why not other approaches

- **Hook `_G.new_mod`:** by the time it returns, the target's
  mod_script has already run inside it. Too late to insert wrapping.
- **`on_all_mods_loaded` event:** fires after all scripts have run.
  Way too late.
- **Replacing `_G.new_mod` entirely:** can't — `create_mod` is `local`
  to vmf_mod_manager.lua.
- **`mod:dofile` interception of the target's source:** would require
  shipping derived code (license burden) and is brittle.

The prototype-patch route is the only one that's both legally clean
(no derived code) and correctly timed.

### Confirmed working

First production use: `la_prefix_patch` v0.2.0-dev, 2026-05-06 — used
to suppress Loremaster's Armoury's three rehook warnings.

---

## Architectural lessons (v0.1.0 → v0.2.0)

VMF runs each mod's `mod_script` inside its own `new_mod()` call
(vmf_mod_manager.lua:95-132), so `get_mod("OtherMod")` from your
script returns nil for any mod that hasn't been registered yet.
Patching VMFMod's prototype methods (which propagate to all future
instances via `__index` lookup) is the right tool for cross-mod
monkeypatching done at our script-load time. v0.1.0-dev tried to grab
LA's instance directly and silently no-op'd; v0.2.0-dev patches the
VMFMod prototype instead, which propagates correctly.
