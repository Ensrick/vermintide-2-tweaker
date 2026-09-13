# Crafting in Modded Postmortems

## 2026-09-12 - #598 owner Cursed frame: source-only candidate, not acceptance

The Modded boolean side channel cannot express a third rarity. WOC's current
Blightreaper instance is Cursed but its loadout wire shadow uses vanilla-safe
promo, so repairing the sender-local boolean did not repair this owner's frame.
The original report explicitly included Blightreaper
([owner report](https://github.com/Ensrick/vermintide-2-tweaker/issues/598#issuecomment-4998872905));
remote/no-WOC promo compatibility does not redefine that owner acceptance.

The bounded candidate reuses the existing Tab post-hook and resolves only the
actual live local human's exact equipped instance after proving that the current
slot owner is the Adventure items interface. It paints Cursed only in the local
widget after checking enabled WOC and the local texture registry. It neither
extends the wire schema nor mutates backend/equipment/shared loadout identity.
Deus/Weaves and remote Cursed remain outside this slice. Missing or throwing
context restores a still-owned old widget override before any attempted lookup;
false/nil prior values and a later writer's value are preserved exactly.

Prevention: installed-hook behavioral tests exercise the real adapter rather
than a copied policy or source-string-only proxy, including immutable snapshots,
first refresh, swaps, respawn/career, wrong owner, missing/throwing dependencies
and resource loss. The runtime synthetic check and bounded retained-field log
are deliberately not renderer PASS claims. Engine method arity and field versus
method evidence is recorded under `ENGINE_SURFACE.md`, Surface 6. Appearance
census claim remains `structural-only`; publication and actual host/client
observations are still required.

## 2026-08-01 — #959 accessory properties displayed independently but did not apply

### Impact

CIM showed Health as available on a second accessory after the first #959 fix,
but clicking it only played the native confirmation sound. The property was not
stored, rendered, or applied. The shipped runtime regression incorrectly passed.

### Root cause

The first fix made picker counts, right-click removal, and Clear layer-aware,
but left the backend mutation helper's `#property_slots < cap` check global.
Five Necklace Health slots therefore exhausted Health for Charm and Trinket.
The native UI plays its sound after invoking the backend write and does not
inspect CIM's result, masking the rejection. The regression fixture manually
appended the sibling slot instead of exercising the production-equivalent
storage policy, so it could not detect the missing seam.

### Correction and prevention

- One pure policy now owns layer-aware write admission, per-key capacity,
  distinct-key capacity, display, removal, and Clear semantics.
- Ordinary weapon properties pass no layer size and retain their global cap.
- The offline and runtime regressions must execute the sibling-layer write with
  one layer already full; fixture-only insertion is forbidden for this class.
- Bounded `[cim:959] property store` diagnostics expose stored, occupied, and
  capped outcomes without chat or per-frame spam.

Engine evidence: `HeroWindowWeaveProperties._add_key_to_slot` invokes the exact
slot write and then plays the sound unconditionally [src:
`hero_window_weave_properties.lua:2402-2460,2654-2664`]. The canonical recurring
pattern is documented as `docs/BUG_CLASSES.md` class 74.
