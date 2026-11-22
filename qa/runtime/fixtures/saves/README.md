# Rig save fixtures (WP-H-08)

A rig plan picks the local save its profile starts from with `"save": "<name>"`:

- `owner-copy` (the default): the owner's `save_data.sav` and `save_data.old` are copied into the rig profile, as before. They are read, never written.
- Any other name: the folder `qa/runtime/fixtures/saves/<name>/`. Its `fixture.json` lists every save file it holds, with SHA-256. `New-RigProfile.ps1` deletes the rig profile's own `save_data.sav` and `save_data.old`, then copies the listed files. It refuses an unknown name, a listed file that is missing or has another hash, and any file in the folder that is not listed.
- A later boot of a plan with `boots` keeps the save the boot before it left, so `save` applies to boot 1 only.

`launcher.config` and `user_settings.config` are not part of a save fixture; they are always built as before.

## What a save holds

Citations are `Vermintide-2-Source-Code/`. The file is the game's `SaveData` table, written by the save manager and read at the title screen.

- Loading: `StateTitleScreenInitNetwork._load_save_data` loads `SaveFileName` (`save_data`, or `save_data_<branch>` off the public branch: `scripts/managers/save/save_data.win32.lua:5-12`). On success `populate_save_data(info.data)` runs. On a load error, for example no file, the game only logs `Load error` and keeps its defaults (`scripts/game_state/title_screen_substates/win32/state_title_screen_init_network.lua:34-48`).
- Top level: `version`, `player_data_version`, `profiles_version`, `talents_version`, `video_version` and `save_loaded` (`save_data.win32.lua:14-21`). `profiles`, `talents` and `player_data` are dropped when their version does not match (`:23-61`).
- `backend_profile_hash` (`:57-59`, set by `scripts/managers/backend/backend_interface_profile_hash.lua:12-13`) and `has_completed_tutorial` (read beside the backend's own flag at `scripts/game_state/title_screen_substates/win32/state_title_screen_main_menu.lua:28`).
- `player_data[<id>]`, where `<id>` is the signed-in **Steam user id** (`Steam.user_id()`, `save_data.win32.lua:66-68`). Each entry starts as a copy of `DefaultPlayerData` (`scripts/settings/player_data.lua:5-41`, `:43-66`): mission selection, favourite and new item ids (backend item ids of the account), new sign-in rewards, controls, recent chat channels, bot spawn priority, viewed dialogues, new keep decoration ids, level preferences and seen shop items.

So a real save carries account identifiers: the Steam user id as a key, plus backend item ids and the profile hash in its values. A fixture made from a real save must have every one of them replaced first, and its README must say how. None is committed today.

## Fixtures

| Name | Files | What the game does with it |
|---|---|---|
| `fresh` | none | Finds no save file, logs the load error, never calls `populate_save_data`, and runs on its defaults (`SaveData.save_loaded` stays `false`: `save_data.win32.lua:17`, set only at `:72`). This is a new player's local state; the account itself is untouched. |
