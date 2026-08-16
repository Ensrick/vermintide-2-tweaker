# Agent bridge (issue #1338)

Live test-agent loop: an external Claude session observes the running game
through framed console-log output, and (Phase 2+) steers it through the OS
clipboard. In-game side is gt_dev's `_gt_agent_bridge.lua` (dev-only, never
promoted); this directory holds the desktop side.

## Phase 1 (this) - outbound telemetry

1. Start the watcher in a terminal (leave it running while playing):

   ```powershell
   .\tools\agent-bridge\agent-bridge-watch.ps1
   ```

2. In-game (gt_dev loaded), chat commands:
   - `/agent_arm [seconds]` - heartbeat line every N seconds (default 2)
   - `/agent_disarm`
   - `/agent_dump <dotted.path> [depth 1-6]` - e.g. `/agent_dump Managers.state.game_mode 2`
   - `/agent_probe_clipboard` - Phase 2 gate; logs a `verdict=LIVE/DEAD/...` line

3. The watcher writes to `%APPDATA%\Fatshark\Vermintide 2\agent_bridge\`:
   - `stream.log` - every `[agent*]` line in order
   - `latest-hb.txt` - newest heartbeat only (cheap polling)
   - `dump-<seq>.txt` - one file per `/agent_dump` frame

   A Claude session reads these with plain file tools while you play.

## Frame protocol

| Line | Meaning |
|---|---|
| `[agent:hb] seq=N t=... state=... level=... pos=... hp=...` | heartbeat |
| `[agent:dump:<seq>] BEGIN <path>` | dump frame opens |
| `[agent:d] <payload>` | dump body line (marker on every line, interleave-proof) |
| `[agent:dump:<seq>] END` | frame closes, watcher writes `dump-<seq>.txt` |
| `[agent:probe] ...` / `[agent] ...` | probe results / lifecycle lines |

All in-game output uses engine `printf`, so it lands in `console-*.log` even
with mod-logging OFF.

## Roadmap (issue #1338)

- **Phase 2**: clipboard-inbound REPL (`eval` / `watch` / tracepoints via one
  bridge-owned dispatcher hook per (Class, method)). Gated on
  `/agent_probe_clipboard` returning `verdict=LIVE` in retail.
- **Phase 3**: function-level hot-patch (swap live function bodies without
  re-registering hooks) + action library.
- **Phase 4**: BUG_TRIAGE_RUNBOOK integration - live-test card evidence
  sourced from bridge frames.
