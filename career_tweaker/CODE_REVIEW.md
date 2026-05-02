# Career Tweaker Code Review (2026-05-01)

Scope: every file under `career_tweaker/` except `bundleV2/`. Reviewer: senior code reviewer pass on v0.2.4-dev.

## Summary

Codebase is small (~280 lines of Lua across three modules) and is in healthy shape after the v0.2.0–v0.2.3 fixes. The talent-swap engine and the `no_random_crits` perk-suppression hook are correct and reversible. **One material bug** is identified in the WHC parry-window extension: the `ActionMeleeStart` hook is broken in three independent ways (wrong field name, wrong method, would-be-clobbered). The "field-patch" engine in the balance module is currently dead code — both registered BALANCE_MODS use hook-based behavior with empty `patches{}`.

VMF infrastructure is sound: the safe-stub fallback for `mod:dofile` is present and the lifecycle hooks call only the stubbed functions, no empty groups, all dropdown options use literal text strings, all `setting_id`s in `_data.lua` have matching localization keys, and no forward-reference bugs. No functional changes were made; only inline review comments were added.

## Confirmed bugs / potential bugs

### POTENTIAL BUG 1 — `ActionMeleeStart` parry-window hook is non-functional

`career_tweaker_balance.lua:80–87` (`mod:hook_safe("ActionMeleeStart", "client_owner_start_action", ...)`):

1. **Wrong field name.** `ActionMeleeStart` inherits from `ActionDummy`, which stores its status extension as `self.status_extension` (no underscore — see `action_dummy.lua:9`). The hook reads `self._status_extension`, which is nil on `ActionMeleeStart`. The if-body therefore never executes.
2. **Wrong method.** `ActionMeleeStart.client_owner_start_action` does **not** set `timed_block` (see `action_melee_start.lua:23–40`). The `t + 0.5` assignment happens in `ActionMeleeStart.client_owner_post_update:65` when the charge-block kicks in. Even if (1) were fixed, the guard `if status_extension.timed_block` would fail on the first attack of a session.
3. **Would-be-clobbered.** Even with both above fixed, `client_owner_post_update` would overwrite our `t + 1.0` with `t + 0.5` on every tick after the start.

The `ActionBlock` half of the hook (`career_tweaker_balance.lua:71–78`) is correct — `ActionBlock.client_owner_start_action:45` does set `self._status_extension.timed_block = t + 0.5`, and `hook_safe` runs after the original.

**Likely fix:** swap to `mod:hook_safe("ActionMeleeStart", "client_owner_post_update", ...)`, read `self.status_extension`, and rewrite the assignment with the now-current `t`.

**Verify in-game:** trigger the WHC parry-crit on a charged attack (the path that funnels through `ActionMeleeStart.client_owner_post_update`) and confirm the window actually doubles — current code almost certainly does not double it for this path.

## Open questions

- **Controller UI refresh.** `_talent_window_instance` only tracks `HeroWindowTalents`. `HeroWindowTalentsConsole` (controller-mode UI, with its own `_update_talent_sync`) is not tracked, so controller users won't get the live UI refresh after a setting change. Acceptable if controller is out of scope; flagging in case it's not.
- **Debug echo.** `mod.on_setting_changed` calls `mod:echo("Setting changed: ...")` on every setting toggle. Is this debug output that should be downgraded to `mod:info`?
- **Mod ID rename.** Code keeps internal ID `"crt"` (correct per recent context — settings persist). Console command `ct_status` collides with the `ct_` convention used for chaos_wastes_tweaker; rename to `crt_status` worth considering for clarity.

## Refactor / cleanup candidates

- **`career_tweaker_balance.lua`:** the entire patch engine (`_originals`, `apply_balance_mods` patch loop, `restore_all_balance_mods`, `BALANCE_MODS[].patches/character/career` fields) is unused. Either delete it, or keep it explicitly as a framework hook for future patch-based balance mods.
- **`career_tweaker.lua:130` console-command comment** said `crt status` but the actual command is `ct_status`. Comment fixed in this pass.
- The `pcall` wrapping `_update_talent_sync` is defensive but probably unnecessary — `on_exit` clears `_talent_window_instance` synchronously. Could simplify to a direct call. Low priority.

## Doc/code mismatches

- `career_tweaker.lua:130` — comment said "crt status" but command is `ct_status`. Fixed in inline comment.
- `CHANGELOG.md` 0.2.0 says "Hooks `HeroWindowTalents.on_enter`/`on_exit`" — that matches code. ✓
- `CHANGELOG.md` 0.2.0 mentions `_update_talent_sync` — matches `HeroWindowTalents._update_talent_sync` in source. ✓

## Settings coherence

| `setting_id` (data.lua) | localization key | runtime read in .lua |
|---|---|---|
| `career_swapping_group` | ✓ | n/a (group) |
| `talent_swap_<career>` × 20 | ✓ all 20 | ✓ `mod:get("talent_swap_" .. career_name)` |
| `talent_balance_group` | ✓ | n/a (group) |
| `balance_zealot_merc_allow_random_crits` | ✓ + `_description` | ✓ `mod:get(...)` in hook |
| `balance_whc_parry_extended_window` | ✓ + `_description` | ✓ `mod:get(...)` in hook |

No orphan setting IDs. No orphan localization keys (verified by inspection — all localization keys correspond to either widgets or the mod itself).

## Hook patterns

- `mod:hook("TalentExtension", "has_talent_perk", ...)` — string-form (lazy resolution), correct because `TalentExtension` may not exist at mod init. Wraps the original and conditionally returns false. Idempotent — toggle takes effect on next call.
- `mod:hook_safe("ActionBlock", "client_owner_start_action", ...)` — string-form, runs after original. Correct overwrite of `timed_block`.
- `mod:hook_safe("ActionMeleeStart", "client_owner_start_action", ...)` — see POTENTIAL BUG 1 above.
- `mod:hook_safe("HeroWindowTalents", "on_enter"/"on_exit", ...)` — string-form, tracks live instance. Correct.

All hooks use string-form class names per CLAUDE.md guidance. ✓

## Balance module loading

Safe-stub fallback present at `career_tweaker.lua:7–13`:

```lua
local ok, balance = pcall(mod.dofile, mod, "scripts/mods/career_tweaker/career_tweaker_balance")
if not ok then
    mod:error("Failed to load balance module: %s", tostring(balance))
    balance = { apply = function() end, restore = function() end, active_count = function() return 0 end }
end
```

The stub provides exactly the three functions called from lifecycle hooks (`balance.apply` from `on_game_state_changed` and `on_setting_changed`; `balance.restore` from `on_disabled`; `balance.active_count` from the `ct_status` command). All three are present. Failure handling is correct. ✓

## Talent swap correctness

### Cross-character flow (`apply_talent_swaps`)

1. **Restore step:** for each previously swapped career in `_talent_swap_originals`, rebind `TalentTrees[profile][index]` and the `activated_ability`/`passive_ability` fields back to their saved originals. Restoration uses **reference rebinding only** (no in-place mutation of tree contents), so it's safe as long as no third party also mutates these slots.
2. **Apply step:** for each career whose dropdown is non-"none", save the current original tree/abilities, then point `TalentTrees[cs.profile_name][cs.talent_tree_index]` at the source's tree, and copy `activated_ability`/`passive_ability` from `src` to `cs` unless the skip-list applies.

Edge cases checked:
- **Self-swap** (e.g. Ironbreaker → Ironbreaker): saves originals, rebinds slot to itself, copies abilities to themselves. No-op. ✓
- **Setting unchanged across calls** (e.g. user changes balance setting, talent swap stays "wh_zealot"): restore puts back original (good), then save the same original (good), then re-apply the swap. Idempotent. ✓
- **Setting changed between two non-"none" values:** restore unwinds previous swap (read from saved original, rebind), then captures the now-restored original, then applies the new swap. Correct. ✓

### Ability skip list

`_WEAPON_ABILITY_CAREERS = { es_questingknight = true }`. The skip activates when **source** is Grail Knight AND `cs.profile_name ~= src.profile_name` (cross-character). Talent tree still swaps; only ability/passive copy is skipped. Logic correct.

**Caveat:** the skip is keyed on `src_name`, not `career_name`. Reading: "swapping FROM Grail Knight TO a different character is unsafe." That's the intended interpretation per the changelog ("Careers with weapon-based abilities skip the ability swap when the target is a different character"). ✓

### UI refresh (`refresh_talent_ui` / `_update_talent_sync`)

- `_talent_window_instance` is set in `HeroWindowTalents.on_enter` (after original runs) and cleared in `on_exit`. Stale-instance risk would require `on_exit` to be missed (e.g. abrupt teardown without VMF firing); pcall guards against it.
- Calls `_update_talent_sync(false)`. Source signature: `_update_talent_sync(self, initialize)`. `false` means "no pulse animation"; `true` would replay the unselected-talent pulse. `false` is correct for a refresh of an already-initialized window. ✓
- Console UI (`HeroWindowTalentsConsole`) not tracked — see Open questions.

### Talent perk suppression

`TalentExtension.has_talent_perk` is hooked to return `false` for `"no_random_crits"` when the toggle is on. Idempotent (no state); reversible (toggle off → original return value). ✓

## VMF widget validation

- **Empty groups:** `career_swapping_group` has 20 sub_widgets. `talent_balance_group` has 2 sub_widgets. Both ≥1. ✓
- **Dropdown option text:** all 21 entries in `talent_swap_options` use literal display strings (e.g. `"Ironbreaker (Bardin)"`), not localization keys. ✓ (matches CHANGELOG 0.2.3 fix)
- **Localization escaping:** no `%` characters in any localization string, so `%%` escaping is not needed. ✓

## Non-obvious things now clarified

- **Why `pcall` around `_update_talent_sync`:** defensive — guards against the window being torn down between `on_exit` firing late and the refresh accessing it. (Probably unnecessary but cheap.)
- **Why hook-based balance over patches:** both shipped balance changes need per-call decisions (not one-shot field rewrites), so the patch engine in BALANCE_MODS is currently bypassed.
- **`on_setting_changed` echo:** flagged as likely debug output (chat-spam risk).
- **`ActionMeleeStart` parry-window hook:** despite appearing to mirror the `ActionBlock` hook, it is functionally a no-op (see POTENTIAL BUG 1).

## Dead code

- `career_tweaker_balance.lua:21–32` — `BALANCE_MODS[*].character` and `BALANCE_MODS[*].career` fields are never read.
- `career_tweaker_balance.lua:21–32` — `BALANCE_MODS[*].patches = {}` is empty for both entries; the patch loop in `apply_balance_mods` and `restore_all_balance_mods` thus does nothing.
- `career_tweaker_balance.lua:79` — `local _originals = {}` and the entire patch-based apply/restore body is unreachable while `patches` is empty. Keep if patch-based mods are planned, otherwise delete.
- `career_tweaker_balance.lua:148` — `BALANCE_MODS = BALANCE_MODS` is exported on the return table but is not referenced from `career_tweaker.lua`. Probably intended as a future hook point for `ct_status` or external introspection.

## Notes for future AI agents

- **Do NOT** flip `itemV2.cfg` `visibility` to `"public"` (intentional per recent context, recorded in feedback memory).
- **Do NOT** change internal mod ID `"crt"` — settings persistence depends on it.
- **Do NOT** rename the `.mod` filename or the `crt`/`ct_` command names without coordinating with the recent VMB migration (CHANGELOG 0.2.4).
- The `ActionMeleeStart` hook is a real bug and a candidate for the next fix. Verify with the Witch Hunter Captain's parry-crit talent on a charged attack before patching.
- Forward-reference scan (per `feedback_lua_forward_reference.md`): all `local function` definitions are above their call sites in both `career_tweaker.lua` and `career_tweaker_balance.lua`. ✓
- `talent_swap_options` is a single shared table referenced by all 20 dropdown widgets — fine because VMF treats `options` as read-only metadata.
- `apply_talent_swaps()` is called from `on_game_state_changed` (every state transition) and from `on_setting_changed` (only `talent_swap_*` events). It's idempotent so re-running is safe and cheap.
- The talent-tree mutation works at the **table-binding** level (`TalentTrees[profile][index] = otherTree`). Anything that reads `TalentTrees` after `apply_talent_swaps()` will see the swapped tree; anything that holds a previously-grabbed reference will not. The UI re-reads on `_update_talent_sync` so the refresh is necessary to catch open inventory windows.

---

Inline comments added: 6 (`-- REVIEW:` × 4, `-- POTENTIAL BUG:` × 1, `-- QUESTION:` × 1) — distributed across `career_tweaker.lua` (3) and `career_tweaker_balance.lua` (3). Plus several explanatory `--` blocks (no marker prefix) where the existing code wasn't wrong but the why-comment was missing.
