# Tweaker: Lobby — Changelog

## v0.1.0-dev (2026-05-19)

Phase 1 implementation. Build passes (4 bundles); in-game smoke test pending first Workshop upload.

**Scaffolding**
- Mod skeleton: `.mod` entry, `.package`, three lua files, `itemV2.cfg` (friends_only).
- VMF settings menu with groups for Slot Reservations, Session Ignore List, Kick on Idle, Message of the Day, Modded Lobby Manifest.

**Features (host-side, hash-neutral)**
- **Slot Reservations** (`_slot_reservations.lua`) — persistent `steam_id → slot` map; auto-kicks non-reserved peers while reservations are pending. Chat: `/lt_reserve`, `/lt_unreserve`, `/lt_reservations`.
- **Session Ignore List** (`_session_ignore.lua`) — two-tier (in-memory session + persistent VMF setting). Auto-kicks on join. Chat: `/lt_ignore`, `/lt_ignore_persist`, `/lt_unignore`, `/lt_ignored`, `/lt_ignore_last`.
- **Kick on Idle** (`_kick_idle.lua`) — position-delta polling (no per-peer idle signal exists); keep-only; 60s warning before kick; whitelist. Chat: `/lt_idle_whitelist`, `/lt_idle_unwhitelist`, `/lt_idle_status`.
- **Message of the Day** (`_motd.lua`) — chunked VMF RPC (respects 500-char string cap) so cross-peer delivery works when the joiner has lobby_tweaker installed. Local fallback otherwise. Chat: `/lt_motd_test`.

**Integration fixes during merge**
- Replaced per-module `mod:hook_safe(_G, "Boot")` (which would silently shadow each other per `vmf-hook-safe-no-chain`) with a `mod.update` pointer-compare pattern that re-registers `on_player_joined_party` whenever `Managers.state.event` rebuilds.
- Normalized chained `mod.update` callbacks to `function(dt)` signature across all modules so the chain doesn't drop args.

**Phase 2 (modded matchmaking)**
- **Manifest broadcast** (`_modded_manifest.lua` + `_known_mods.lua`) — enumerates loaded VMF mods, resolves mode (`R` required / `C` cosmetic / `H` host_only) via per-mod `_lt_mode` self-declaration → `_known_mods` fallback table → default `R`, serializes per `PHASE2_PROTOCOL.md` (tab-delimited lines, chunked into `ltw_p` / `ltw_n` / `ltw_m0..N-1` keys), publishes via `LobbyHost:set_lobby_data`. Re-publishes on setting change + 60s heartbeat, throttled to 500 ms. Diagnostic: `/lt_manifest_dump`.
- **Failed-join reveal** (`_failed_join_reveal.lua`) — hooks `StateLoading.create_popup` (`state_loading.lua:2447`), gates on `error_key == "failure_start_join_server_incorrect_hash"`, fetches the host's manifest via `LobbyInternal.get_lobby_data_from_id_by_key`, diffs against local mods, replaces the vanilla "Game version mismatch" popup with our own listing missing `R` mods + version mismatches, "Host also has N cosmetic mods" footer, and an "Open Workshop" button pointing at the first missing mod (or the Workshop hub as fallback). Diagnostic: `/lt_manifest_probe <lobby_id>`.

**Before first upload (still needed):**
- Drop a `preview.jpg` (≤1 MB) into the mod root.
- Finalize Workshop title/description — current copy is a placeholder.
- First `vmblauncher upload lobby_tweaker` creates the Workshop item and back-fills `published_id` in `itemV2.cfg`. Subsequent deploys then work.

**Pending in-game smoke test** (gated on the above):
- VMF menu page renders with all 5 groups, no widget-id collisions.
- Banner echoes `[Tweaker: Lobby] v0.1.0-dev loaded.` on game start.
- Each Phase 1 chat command parses + bails cleanly when not host.
- Phase 2: with a second machine on the friend list, a lobby_tweaker-less joiner attempting to join a lobby_tweaker host should see the "you are missing X" popup instead of the vanilla hash-mismatch message.
