# Lyndsey LA Bridge Diagnosis (cosmetics_tweaker v0.9.0.12-hotfix)

## Root cause (1-line)

Lyndsey has Loremaster's Armoury **subscribed but DISABLED** in the launcher,
so VMF never initialises the mod and `get_mod("Loremasters-Armoury")` returns
`nil` on her PC. There is nothing wrong with cosmetics_tweaker, the network
broadcast, or the variant data on either side.

## Confirmed LA state on both PCs

| PC | log line | enabled | VMF Init line |
|---|---|---|---|
| HOST  (Dan) | `mods[65] = (id=2789506353, name="Loremaster's Armoury", enabled="true",  last_updated="12/9/2024 12:48:11 AM")` | `true`  | `Init VMF mod 'Loremasters-Armoury' [workshop_name: 'Loremaster's Armoury', workshop_id: 2789506353]` (host log L1094) |
| CLIENT (Lyndsey) | `mods[16] = (id=2789506353, name="Loremaster's Armoury", enabled="false", last_updated="12/9/2024 12:48:11 AM")` | `false` | **NEVER FIRES** — grep `Init VMF mod 'Loremasters-Armoury'` in her log returns zero hits |

Identical `last_updated="12/9/2024 12:48:11 AM"` confirms both PCs have the
exact same Workshop revision of LA on disk — H1 (version mismatch) is ruled
out. H3 (typo / case) is also ruled out — `skin_list.lua:42` contains
`Kruber_bret_shield_basic2_Luidhard01` verbatim.

## Receiver-side evidence the bridge is dormant on Lyndsey

Lyndsey's log, after cosmetics_tweaker loads at 01:19:31.437:

```
01:24:51.850 [MOD][cosmetics_tweaker][INFO] [LA bridge] dependency missing: Loremaster's Armoury. bridge will stay dormant.
```

That message is emitted by `cosmetics_tweaker.lua:4789` only when
`get_mod("Loremasters-Armoury")` is nil. With the bridge dormant:

* `_la_bridge_init_done` never flips true
* `LA_BRIDGE.register_all()` never runs
* IML entries for LA variants are never registered on Lyndsey's mirror
* On every husk wield, the `[husk-mesh-swap probe]` code at lines 2281-2322
  finds an entry in `_la_equips_by_peer` (because the host's
  `cos_la_apply` broadcast still arrives and is cached) but
  `la and la.SKIN_LIST and la.SKIN_LIST[entry.armoury_key]` evaluates to nil
  because `la` itself is nil. That hits line 2299 and logs:
  `miss: variant Kruber_bret_shield_basic2_Luidhard01 not in LA.SKIN_LIST`.

Identical mechanic for hats: `_apply_la_on_unit` (line 3877) calls
`_resolve_la_variant(armoury_key)` at line 3881, gets nil back from line 3861
(`if not la or type(la.SKIN_LIST) ~= "table" then return nil, nil end`),
and bails at line 3883 — Lyndsey sees the wrong hat colour because the LA
re-paint never runs, so the vanilla material stays on the attachment.

The variants ARE present in skin_list.lua on Lyndsey's disk (confirmed:
`Kruber_bret_shield_basic2_Luidhard01` at L42; `Kruber_Hippogryph_helm_*` at
L1147-1193). They're just unreachable because the host mod that owns the
table never loaded.

## H2 / H4 ruled out

H2 (partial SKIN_LIST): cannot apply — table never initialises on her side
at all; the issue is binary, not partial.

H4 (third-party mutation): nothing on Lyndsey's load order touches
LA.SKIN_LIST since LA itself is not loaded — there's no table to mutate.

## Recommended user-facing fix

Tell Lyndsey:

> Open the Mod Launcher → Mods list → find "Loremaster's Armoury" (Workshop
> ID 2789506353) → tick its checkbox so it shows **enabled** → save load
> order → restart VT2. You already have it subscribed; it just isn't ticked.

After that, on next host session the existing `cos_la_apply` rebroadcast +
hot-join replay path will paint the shield and hat correctly with no other
action needed. No code change is required to unblock her — this is purely a
launcher-config oversight on her PC.

## Code patch suggestions (read-only — not applied)

The mod already prints the dormant-bridge warning at log level INFO (line
4789) but Lyndsey did not notice it because it's in the file log, not chat.
Two low-risk improvements, listed by ROI:

### A. Promote the "LA missing" warning from `mod:info` to `mod:echo` (CHAT)

Mirror the existing MoreItemsLibrary chat warning at line 4785. Replace the
single-line block at 4788-4790 with:

```lua
if not has_la then
    mod:echo("[cosmetics_tweaker] Loremaster's Armoury is NOT subscribed or NOT enabled. LA cosmetics from other players will not paint on your screen. Subscribe + enable: https://steamcommunity.com/sharedfiles/filedetails/?id=2789506353")
    mod:info("[LA bridge] dependency missing: Loremaster's Armoury. bridge will stay dormant.")
end
```

This is the single highest-value change — the same advice already exists for
MIL on the line above; LA was simply left at `info`-only.

### B. Per-variant graceful-degradation chat warning on `husk-mesh-swap` miss

When a husk wield references an LA `armoury_key` we can't resolve locally,
emit ONE-PER-VARIANT chat message naming the variant the host equipped that
we can't render. The variant key is already in hand at the two `miss` sites.

In `cosmetics_tweaker.lua` near the top (after existing module locals),
introduce a dedupe table:

```lua
local _la_miss_warned = {}
local function _warn_missing_la_variant(armoury_key, why)
    if not armoury_key or _la_miss_warned[armoury_key] then return end
    _la_miss_warned[armoury_key] = true
    local has_la = get_mod("Loremasters-Armoury") ~= nil
    if not has_la then
        mod:echo(string.format(
            "[cosmetics_tweaker] Host equipped LA cosmetic %q but Loremaster's Armoury is not enabled on your PC — it will render as vanilla. Enable LA (Workshop 2789506353) and restart.",
            armoury_key))
    else
        mod:echo(string.format(
            "[cosmetics_tweaker] Host equipped LA cosmetic %q that your local LA install doesn't know about (%s). Update Loremaster's Armoury via Steam.",
            armoury_key, why or "missing from SKIN_LIST"))
    end
end
```

Then call it at:

* `cosmetics_tweaker.lua:2299` (the husk-mesh-swap miss site)
* `cosmetics_tweaker.lua:3883` (the `_apply_la_on_unit` bail site —
  covers `hat`, `armor`, and `illusion` kinds, which today bail silently)
* `cosmetics_tweaker.lua:4168` (the `_install_skin_loadout_safety`
  variant-resolve site)

Mechanism note: the `kind="texture"` ("armor") path already degrades to
"vanilla mesh, no paint" today because `apply_new_skin_from_texture` is
LA's own function and is simply skipped when LA isn't there; the request is
to add the *user-visible* warning so the silent fallback is no longer
silent. The mesh-swap `kind="unit"` path needs no behaviour change either —
the receiver already keeps `result.left_hand_unit` at the vanilla value
when the LA mesh-swap branch can't apply (the early-return at line 2319 is
the only path that overrides it).

No structural change to the bridge, RPC schema, or broadcast logic is
needed; LA's absence on a single peer is correctly handled as
fall-through-to-vanilla already — only the user-facing signalling is weak.
