# VMF + user_settings.config — reference for GUI Tweaker (gut)

Durable notes on how **VMF (Vermintide Mod Framework)** and the game's
`user_settings.config` actually work, scoped to the Mod Tweaker reimplementation in
`gut` / `gut_dev`. Maintained so we STOP re-discovering the same facts every session.
Every entry is tagged **CONFIRMED** (verified from source/file) or **TBD** (unverified —
go verify in the VMF source before relying on it).

> **Read the real VMF source, never DMF.** VMF source (loose lua) lives in the repos at
> `misc-vermintide-mods/Vermintide Mod Framework/scripts/mods/vmf/`. The Workshop copy is
> BUNDLED (`.mod_bundle`, not loose lua), so the repo clone is the place to read it.
> `darktide-mods/DMF/` is the Darktide FORK — names/structure may differ; do not use it as
> a VMF reference.

## Accessing VMF from a mod — CONFIRMED
- `local vmf = get_mod("VMF")` (HideBuffs, ModdedProgression, SpawnTweaks all do this).
- Known VMF functions seen used:
  - `vmf.generate_keybinds()` — regenerates the active keybind callbacks (`vmf_loader.lua:61`). CONFIRMED exists.
  - `vmf.save_unsaved_settings_to_file()` — flushes settings to `user_settings.config` (ModdedProgression). CONFIRMED exists.
- **TBD:** the exact VMF fn that registers/updates ONE mod keybind from its keys (DMF's is `add_mod_keybind`; VMF's name is unverified — find it in the VMF source).

## Keybind VALUE format (stored in user_settings.config) — CONFIRMED
- A keybind setting's value is an ARRAY of key-name strings: `[ primary_key, modifier... ]`.
- **Primary key is FIRST**, modifiers AFTER. Modifiers are NORMALIZED lowercase:
  `"ctrl"`, `"alt"`, `"shift"` (NOT `"left ctrl"`). Key names are LOCAL names.
- Examples from the user's config: `["c","ctrl"]` = Ctrl+C, `["f8"]` = single key. `[]` = unbound.

## Keybind RE-REGISTRATION (the gotcha behind #123) — CONFIRMED behavior, TBD exact call
- Setting a keybind value via `mod:set(setting_id, value)` updates the saved value AND the row
  text, but **does NOT make the bind fire** — VMF does not re-register the binding on a plain set.
- In-game evidence (user, 2026-06-27): after assigning keys the text updates correctly but the
  bind never works; it only works when set through VMF's own native menu. Clearing shows "unbound"
  text but doesn't actually clear the binding either.
- So gut's Mod Tweaker, after a keybind change, MUST replicate VMF's native menu. CONFIRMED from
  VMF source `unpacked/6002BA9E6738B57B.lua` (= vmf_options_view, ~line 734) — three steps:
    1. `vmf.add_mod_keybind(mod_obj, setting_id, { keys=keys, type=keybind_type, trigger=keybind_trigger,
       global=keybind_global, function_name=..., view_name=..., transition_data=... })` — re-register.
       **CONFIRMED in-game (v0.2.101 [gut:keybind] log):** it is `vmf.add_mod_keybind(MOD, setting_id, data)`
       — a VMF function with the mod as the FIRST ARG. It is NOT `mod_obj:add_mod_keybind(...)` (that errors
       `attempt to call method 'add_mod_keybind' (a nil value)`). `vmf = get_mod("VMF")`.
    2. `mod_obj:set(setting_id, keys, true)` — persist the value to user_settings.config.
    3. `get_mod("VMF").generate_keybinds()` — activate (DOT call, no self; confirmed in-game `gen_ok=true`).
  Order matters: register FIRST; only persist + generate if it landed (a failed register that still set the
  value + generated left an inconsistent state that crashed v0.2.101). Empty `keys = {}` unbinds.
- VMF keybind module: `unpacked/D195174C8CBE0E3C.lua` (`add_mod_keybind`, `generate_keybinds`,
  `check_keybinds`, `build_keybind_string`, `can_bind_as_primary_key`, `get_key_id`). raw struct uses
  `keys` / `primary_key` / `modifier_keys`. Validator `unpacked/BEDBA3685B40C8A4.lua`: max 4 elements,
  modifiers ONLY `"ctrl"/"alt"/"shift"`. Capture (`set_new_keybind`) uses `Keyboard.any_pressed` +
  `first_pressed_button` + `get_key_id`, and normalizes left/right ctrl→ctrl etc.
- VMF keybinds apply IMMEDIATELY (no Apply button). gut should commit a keybind on capture/clear, NOT
  stage it.

## user_settings.config — VMF logging output modes — CONFIRMED
- Keys: `output_mode_echo`, `output_mode_error`, `output_mode_warning`, `output_mode_info`, `output_mode_debug`.
- Values: `0 = disabled`, `1 = log`, `2 = chat` (inferred), `3 = log + chat`.
- User preference (set 2026-06-27): **echo = 3** (log+chat), all others (error/warning/info/debug) = **1** (log).
- **CAVEAT:** VT2 OVERWRITES `user_settings.config` on exit. Editing the file while the game is
  running loses the change. Edit with the game CLOSED, or set via the in-game VMF menu.

## gut Mod Tweaker keybind rendering — CONFIRMED
- Live impl: **ModTweakerView** (`_mod_tweaker_view.lua`), instantiated by `gui_tweaker_dev.lua` (~840).
  `HeroViewStateModTweaker` (`_mod_tweaker_state.lua`) is a parallel impl that still builds keybind
  read-only — NOT the live path; don't edit it expecting an effect.
- Row dispatch: `ModTweakerView:_build_node_row` (wtype branch). Keybind currently reuses the
  **dropdown** row shape (has a down-arrow → looks like a dropdown; #123 visual gripe — should look
  like a keybind FIELD like the native settings menu).
- Keybind widget definition fields (`*_data.lua`): `type="keybind"`, `keybind_trigger` (e.g. "pressed"),
  `keybind_type` (e.g. "function_call"), `function_name`, `default_value={}`.
- `_format_keybind_value(val)` (view ~155) renders the array as a combo string / "unbound" (#95 handled).
- Capture helper `_poll_keybind_combo()` (view ~167) reads `Keyboard.button(i)`/`button_name(i)`, emits
  `[ main, normalized-mods ]`. **Open question:** are `Keyboard.button_name` outputs already the LOCAL
  names VMF expects, or do they need `local_to_global`/normalization? Verify against the VMF source.

## Open items (verify next, then fold the answers in here)
- VMF's exact register-one-keybind fn name + signature (to call after committing a value).
- The runtime keybind-data struct VMF expects.
- Whether ESC-clear / right-click-clear must ALSO call the register fn with an empty/removed binding.
