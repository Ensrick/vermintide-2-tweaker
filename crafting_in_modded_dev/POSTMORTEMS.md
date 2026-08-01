# Crafting in Modded Postmortems

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
