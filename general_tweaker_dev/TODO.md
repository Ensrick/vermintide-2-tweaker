# General Tweaker — TODO / idea backlog

> **REFERENCE ONLY — not current status.** Unchecked and completed entries may
> be stale. GitHub Issues is the sole current tracker; retain this file only for
> design evidence that is not yet captured in an issue.

Ideas captured here are **not yet scoped or implemented** — investigation pointers
only. Confirm every internal against the decompiled source
(`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`) before writing code; nothing
below has been verified yet.

---

## Idea: "Prioritize specials when tagging" toggle

**Captured:** 2026-06-16 (idea only, no implementation)

**What the user wants:** a toggle that, when the player tags/pings, always highlights a
**special** in preference to elites, monsters, items, and regular enemies — even when the
crosshair is pointed at one of those instead. So if a special is anywhere in the taggable
set, the tag snaps to / calls out the special first.

**Intended priority (to confirm with user):**
`special` > everything else (elite / monster / regular enemy / item / pickup).
Open question whether monsters should outrank or underrank specials, and whether items
should be tag-able at all when a special is present. User wrote "before elites/monsters/
items, etc." → specials win over all of those.

**Investigation pointers (UNVERIFIED — grep source before trusting any of these):**
- Find the smart-tagging / ping target-selection path. Candidate search terms:
  `smart_tag`, `PingSystem`, `ping_`, `outline`, `SmartTargetSelectionExtension`,
  `ping_settings`, `tag` in `scripts/`. Identify how the game picks the target (raycast
  under crosshair vs nearest-in-cone vs priority list).
- Determine how a breed is classified as a "special": look for a breed category/flag on
  `Breeds[...]` (e.g. a `special`/`boss`/`elite` field) in `scripts/settings/breeds/`.
  Use that classification, do NOT hardcode a breed name list (gutter runner, packmaster,
  ratling, warpfire, blightstormer, assassin, leech, flamer, sorcerer, etc.) unless the
  category flag turns out unreliable.
- Decide the override mechanism: (a) re-rank an existing candidate list the engine already
  builds, or (b) hook the target-selection function and substitute a nearby special when
  one exists. Prefer (a) if the engine exposes a priority/candidate list.

**Open design questions:**
1. **Scope of "taggable set":** only targets within the normal tag range/cone, or widen it
   for specials? Probably keep vanilla range — just re-rank within it. Widening range is a
   bigger gameplay change and a possible "cheat" perception.
2. **Crosshair override:** does it fully ignore what the crosshair is on (always grab the
   special), or only redirect when the crosshair isn't on a valid higher-priority target?
   Leaning: always prefer special within range, since that's the stated intent.
3. **Granularity:** single on/off toggle vs a small priority config (e.g. per-category
   checkboxes / an ordered list). Start with one toggle; expand later if wanted.
4. **Networking:** tagging produces a networked ping. Confirm this is client-side target
   selection (each player tags for their own session) so no host-sync / version-gate risk.
   Almost certainly client-only, but verify before assuming.
5. **VMF UI:** plain checkbox — no slider/mutex needed, so no `vmf_options_view` gotchas.
6. **Interaction with vanilla "no special in sight" case:** when there's no special, behave
   exactly like vanilla tagging (tag whatever the crosshair is on).

**Why it's a good fit for `gt`:** pure client-side QoL, Lua-only (hot-reload-friendlier than
wt/cosmetics), no DLC-gate surface, no backend writes. Matches gt's existing "QoL toggles"
character.

**Next step when picked up:** confirm priority order + crosshair-override behavior with the
user, then read the ping/smart-tag source to choose re-rank vs hook. Consider filing a
GitHub Issue (repo rule: pending work → Issues) at that point.
