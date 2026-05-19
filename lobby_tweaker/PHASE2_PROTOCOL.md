# Lobby Tweaker — Modded Manifest Protocol v1

## Purpose

The host publishes the loaded VMF mod set to Steam lobby user_data so a client whose join fails the network-hash check can fetch the manifest **directly from the lobby ID** (no peer-to-peer comms required) and tell the user exactly which mods are missing.

The host's manifest must be readable BEFORE any successful peer connection, because the vanilla hash mismatch (`failure_start_join_server_incorrect_hash` at `state_loading.lua:1084`) fires before VMF mod-sync runs.

## Steam lobby_data keys

Host writes via `LobbyHost:set_lobby_data(table)` (`lobby_host.lua:139`).
Client reads via `LobbyInternal.get_lobby_data_from_id_by_key(lobby_id, key)` (`lobby_steam.lua:70-76`) — does NOT require a successful join.

| Key | Value | Notes |
|---|---|---|
| `ltw_p` | `"1"` | protocol version; bump on incompatible format change |
| `ltw_n` | `"<N>"` | string of integer 0..MAX_CHUNKS — number of chunks that follow |
| `ltw_m0`..`ltw_m{N-1}` | chunk_str | UTF-8 string ≤ 200 chars each (conservative under Steam per-key limit ~256) |

The reader assembles the full manifest text by concatenating `ltw_m0`..`ltw_m{N-1}` in order.

## Manifest format

One mod per line, separated by `\n` (LF). Each line:

```
<id>\t<version>\t<mode>\t<workshop_id>\t<display_name>
```

Fields separated by `\t` (TAB). No field may contain TAB or LF.

### Field values
- `id` — internal VMF mod id (passed to `new_mod(id, ...)`); lowercase ASCII, ≤32 chars.
- `version` — whatever the mod exposes as `MOD_VERSION` (or similar). ≤16 chars; truncate if longer.
- `mode` — one of `R` / `C` / `H`. See below.
- `workshop_id` — Steam UGC PublishedFileId as digit string. `0` if unpublished.
- `display_name` — UTF-8 human-readable; ≤64 chars; truncate with `…` if longer.

### Mode values
- **`R` — client_required**. Joiner needs the mod to play. Drives the headline "you are missing X, Y, Z" message.
- **`C` — cosmetic**. Joiner is fine without it; they just won't see what the host's mod renders. Surfaced as a "host also has these cosmetic mods" footer line.
- **`H` — host_only**. Doesn't affect clients (e.g. host-side debug tools). Shown only in verbose mode.

## Mode discovery (host)

For each loaded mod, resolve mode in this order:

1. **Mod self-declaration** — if the mod's table sets `mod._lt_mode = "R" | "C" | "H"`, use that. Mod authors future-proof by adding one line.
2. **Fallback table** — `_known_mods.lua` ships a curated map of common third-party mod_ids → mode (e.g. `weapon_tweaker = "R"`, `numeric_ui = "C"`).
3. **Default** — `R` (client_required). Surface missing-by-default rather than silently. False positives are fixable by adding the mod_id to the cosmetic list.

## Sizing

- Steam per-key value limit ~256 chars → use ≤200 to leave headroom.
- Total user_data ~8 KB → with ~150-byte average per entry (id+ver+mode+wsid+name+tabs) ⇒ ~50 mods worst-case across ~40 chunks.
- If a host's manifest exceeds the budget, drop entries in this order: `H` first, then `C`, then truncate `R` low-priority by display name. Always keep `ltw_n` accurate.

## Re-publish triggers (host)

- On lobby creation / host startup.
- On any VMF setting change (a mod can be toggled enabled/disabled mid-game in some cases). Throttle to once per 500 ms.
- On a periodic timer (e.g. 60s) as a self-heal in case Steam dropped a key.

## Client fetch flow

When the client's lobby join is about to fail with `failure_start_join_server_incorrect_hash`:

1. Read `LobbyInternal.get_lobby_data_from_id_by_key(target_lobby_id, "ltw_p")`. If absent or != `"1"` → fall back to vanilla popup.
2. Read `ltw_n`, parse integer. If 0 or absent → fall back.
3. Read `ltw_m0..ltw_m{n-1}`, concatenate.
4. Split on `\n`; for each line split on `\t` and parse fields. Skip malformed lines.
5. Diff against the local mod set (enumerate via `Managers.mod._mods` same way the host did).
6. Replace (or supplement) the vanilla popup with our enriched view:
   - **Body**: "Cannot join — you are missing N mods required by the host:"
   - One line per `R` mod the local client lacks: `• <display_name> (v<version>) — workshop:<id>`
   - If any `C` mods are also missing: footer line "Host also has N cosmetic mods you don't (gameplay unaffected)."
   - Buttons: "Open Workshop page for first missing" (opens `steam://url/CommunityFilePage/<workshop_id>`), "Cancel".

## Future changes

Anything incompatible → bump `ltw_p`. Old clients fall back to vanilla on unknown version. Backwards-compatible additions (e.g. new TAB-separated field appended after `display_name`) are safe within v1 — readers MUST ignore unknown trailing fields.
