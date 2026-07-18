-- issue 52 object-set census ([ct:skull52]). Observation-only: called from the
-- GameModeHelper.get_object_sets hook in the entry, BEFORE the issue-156 'adventure'
-- enable mutates the spawned list, so every line records the RAW engine decision.
--
-- PREMISE CORRECTION (2026-07-18). The 0.7.218-dev arming asserted the Tower of
-- Treachery skulls were the `gargoyle_head` level_event pickup. That is wrong and
-- would have mis-read any evidence the probe returned:
--   * `gargoyle_head` (`Pickups.level_events`, `pickups.lua:440-453`) is a dlc_portals
--     asset. It backs the collect-4 `portals_survive` mission
--     `mission_restore_the_gargoyle_heads` (`penny_level_settings_part_1.lua:61-65`)
--     and is voiced only in the `dlc_drachenfels_portals` dialogue set.
--   * Tower of Treachery ships in the `wizards` DLC, not `penny`, and its skulls are
--     not a Pickups entry at all. They are level-flow interactables baked into the
--     dlc_wizards_tower level binary that call `flow_callback_on_tower_skull_found`
--     -> `Managers.state.achievement:trigger_event("on_tower_skull_found")`
--     (`flow_callbacks.lua:5627-5629`); 10 of them complete `achievements.tower_skulls`
--     (`achievement_templates_wizards_part_2.lua:48-69`).
-- Nothing in the decompile names their object set: set membership lives in the level
-- binary, so this census is the only way to identify it.
--
-- WHY THE CENSUS IS NOT DEUS-ONLY. A single deus run cannot tell you WHICH set carries
-- the skulls, only what the set list looks like. The skull-bearing set is found by
-- DIFFING a vanilla-adventure run of dlc_wizards_tower against an injected deus run of
-- the same level: a set that is spawned=true under adventure and spawned=false under
-- deus, with a non-zero unit count, is the fix target. `mode=` keeps the two runs
-- distinguishable in one log. Per `game_mode_helper.lua:58-111` the `flow_` / `team_` /
-- `shadow_lights` sets spawn regardless of game mode, so a difference can only appear on
-- a plain-named set gated by `GameModeSettings[mode].object_sets`; `kind=` marks those
-- always-on sets and `units=` (the set's unit-index count, same source) dismisses empty
-- ones.
--
-- printf, never mod:info: the user runs with mod logging OFF.
local mod = get_mod("ct_dev")
local M = {}

-- object_sets      : map set_name -> { type = <"" | "flow" | "team">, key, units }
-- spawned_object_sets : array of set names the engine will actually spawn
-- Returns true when a census was emitted (the level was an injected-adventure base).
function M.census(object_sets, spawned_object_sets, level_name, game_mode_key, base_resolver)
    if type(object_sets) ~= "table" or type(spawned_object_sets) ~= "table" then return false end
    if type(base_resolver) ~= "function" then return false end

    local lth = Managers and Managers.level_transition_handler
    local cur_key = lth and lth.get_current_level_keys and lth:get_current_level_keys()
    if type(cur_key) ~= "string" then return false end

    -- Gate on the CURRENT level key rather than the issue-156 level_name match, so the
    -- hero-sublevel calls at `state_loading.lua:1438` are captured too.
    local ok, base = pcall(base_resolver, cur_key)
    if not ok or not base then return false end

    local spawned_lookup = {}
    for _, s in ipairs(spawned_object_sets) do spawned_lookup[s] = true end

    local names = {}
    for set_name in pairs(object_sets) do names[#names + 1] = set_name end
    table.sort(names)

    pcall(printf, "[ct:skull52] key=%s level_name=%s mode=%s object_sets=%d spawned=%d",
        tostring(cur_key), tostring(level_name), tostring(game_mode_key),
        #names, #spawned_object_sets)

    for _, set_name in ipairs(names) do
        local entry = object_sets[set_name]
        local units = type(entry) == "table" and entry.units or nil
        pcall(printf, "[ct:skull52]   set=%s spawned=%s units=%s kind=%s",
            tostring(set_name),
            tostring(spawned_lookup[set_name] == true),
            tostring(type(units) == "table" and #units or "?"),
            tostring(type(entry) == "table" and entry.type or "?"))
    end

    return true
end

return M
