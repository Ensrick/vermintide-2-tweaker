# Bot designated-loadout victory pose (#232)

## Source defect

`PlayerBot.spawn` in `scripts/managers/player/player_bot.lua` declares
`local is_bot = true` and passes it when fetching `slot_skin` and `slot_frame`.
Its immediately adjacent `slot_pose` call omits the third argument. The item
interface therefore selects the human base loadout instead of its refreshed bot
loadout, and the wrong pose is stored on the bot cosmetic extension for the
end-of-level podium.

## Repair boundary

GUT brackets the synchronous `PlayerBot.spawn` call and observes
`BackendUtils.get_loadout_item`. Only a `slot_pose` lookup with a missing
`is_bot` argument inside that exact call context is changed to `true`. Explicit
arguments, human calls, skin/frame calls, and all other slots delegate unchanged.
The context counter is unwound even if vanilla spawn raises an error.

This is narrower than replacing the spawn method and preserves all vanilla
inventory, pose, cosmetic-extension, scoreboard, and podium logic. It introduces
no RPC, schema, persisted state, or new pose identity. In Adventure/Deus the item
interface resolves the designated bot preset; in mechanisms where bot presets are
unsupported it keeps the same vanilla fallback used by bot skin and frame.

## Solo verification

For a career assigned to a bot, make the designated bot loadout use a victory
pose different from the human-selected loadout. Complete an Adventure mission
with that bot and confirm the podium uses the designated pose. The log should
contain one bounded `[gut:232]` repair line for that career. Run
`/gut_regression_test` and confirm `issue232_bot_designated_victory_pose` passes.
