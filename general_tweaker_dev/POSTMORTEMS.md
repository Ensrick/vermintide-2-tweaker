# General Tweaker — Postmortems

Incident writeups for bugs whose *diagnosis* (not just the fix) taught something
worth not relearning. One entry per incident: symptom, root cause, why it was
hard, prevention. Fix-only detail lives in `CHANGELOG.md`; reusable patterns are
promoted to repo `docs/BUG_CLASSES.md`. Newest first.

---

## #275 — Nurgloth final-phase-at-full-health softlock (collapsing `and`/`or` guard)

- **Closed:** 2026-07-06, gt_dev v0.2.193-dev (user-confirmed in-game on v0.2.191-dev).
- **Fix commit:** `b166251` (gt). BUG_CLASSES class 26. Adjacent (confirmed-correct) work: gut cutscene wired-`on_skip` policy, commit `d4784dc`.

### Symptom
On The Enchanter's Lair (`dlc_castle`), Nurgloth entered his final offensive
phase at 100% health and his health floored (~66%, the intro's `set_min_health_
percentage(0.65)` gate never lowered) — the fight was unbeatable. Reproduced in
Chaos Wastes runs of the level. The report pointed the finger at gut's Skip
Cutscenes because the boss's appearance cinematic was involved.

### Root cause
gt's Creature Spawner ports a Drachenfels/Nurgloth phase hook whose body had
collapsed to a constant:
```lua
mod:hook(BTConditions, "transitioned_one_third_health", function(func, ...)
    return (_gt_cs_is_in_level("dlc_castle") and func(...)) or true
end)
```
Intended: outside `dlc_castle`, force `true` so a Creature-Spawner-spawned
Nurgloth skips its arena-specific defensive phase; inside the real arena, defer
to vanilla. But `(true and false) or true == true`: when vanilla correctly
returned `false` (boss has NOT yet passed the one-third transition), the `or true`
overwrote it. The condition was CONSTANT TRUE everywhere, forcing the BT straight
into the final-offense branch (`chaos_exalted_sorcerer_drachenfels_behavior.lua:239`)
at full health. `bt_node.lua:55-57` name-resolves conditions every evaluation, so
the collapsed guard poisoned every tick — a total, not intermittent, break.
Fix: explicit branch (`if in_arena then return func(...) end return true`) via the
pure helper `mod._gt_cs_one_third_wrapper`, preserving vanilla's multi-return.

### Why it took ~13 attempts
1. **Wrong subsystem.** The symptom surfaced around Nurgloth's cinematic, so the
   first ~13 attempts chased gut's Skip Cutscenes (auto-unlocking a cutscene with
   no wired `event_on_skip`). That was a *real, separate* bug (#275's gut half,
   fixed by the wired-`on_skip` gate, commit `d4784dc`) — but it was not what
   floored the boss's health. Two bugs wearing one issue number.
2. **Two wrong level-key identifications.** The arena was misidentified twice
   before `dlc_castle` (and its CW `dlc_castle_*` variants) was pinned as the
   real Enchanter's Lair key — costing repro cycles on the wrong level.
3. **The probe had to be breed-field-wrapped.** Direct `mod:hook` on
   `AiBreedSnippets` table functions does NOT fire: the breed captures those
   functions as DIRECT references at breed-load time
   (`breed_chaos_exalted_sorcerer_drachenfels.lua:119`, dispatched via
   `ai_simple_extension.lua:227`), so a later table-entry hook is bypassed
   (the upvalue-capture class — repo CLAUDE.md § "Hooks that silently no-op").
   The only probe that saw the truth read the blackboard/breed fields directly
   (`[et:275] HOOK sorcerer_drachenfels_go_offensive_intense | hp_pct=1.000 ...
   two_thirds_done=nil one_third_done=nil`), which finally showed the final phase
   entered at full health with transitions never flagged.
4. **BT hooks are captured as upvalues at tree construction.** `BTConditions`
   hooks must be installed BEFORE `create_all_trees` runs, or the tree holds the
   original function; wrap-before-create is required for the phase hook to take
   effect at all — another reason early attempts saw no change.

### Prevention
- **BUG_CLASSES class 26** ("Collapsing `and`/`or` guard in a hook wrapper")
  codifies the idiom, the diagnosis order (grep `BTConditions` hooks FIRST on any
  phase-machine misbehavior), and the explicit-branch fix template.
- **Repo idiom sweep** (`\(.*and func\(.*\)\) or `) ran across every active mod's
  hooks at v0.2.191-dev; only this line was a genuine collapsing-guard bug (the
  other same-shape lines defer a truthy BT-status/table/discarded value, so their
  `or <default>` tail is harmless).
- **Truth-table regression check** `gt_cs_transitioned_one_third_not_forced`,
  wired to the SAME helper the hook calls, so the collapse can never silently
  return again.
- **`[et:275]`-style phase probes:** for boss/AI phase machines, prefer a
  breed-field-wrapped blackboard probe over table-function hooks that the breed's
  captured references bypass.
