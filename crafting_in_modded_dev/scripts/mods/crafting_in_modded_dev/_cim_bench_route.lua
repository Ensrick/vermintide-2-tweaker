--[[
#80 (WP-CIM-03): the HeroView route that opens the standard Keep bench.

HeroView.post_update_on_enter passes menu_state_name to _change_screen_by_name,
which asserts when the name is not a screen
(Vermintide-2-Source-Code/scripts/ui/views/hero_view/hero_view.lua:477-480,
499-510). The screens are overview, achievements, loot, keep_decorations,
weave_forge and handbook (hero_view_definitions.lua:74-166); "forge" is a
window layout of the overview screen (states/hero_window_layout.lua:72),
selected through menu_sub_state_name (hero_view.lua:82-94,
states/hero_view_state_overview.lua:252-255). Vanilla's own bench interaction
uses the same pair (scripts/unit_extensions/generic/interactions.lua:2203-2207).

Pure: no engine globals.
]]

local M = {}

-- A new table on every call, so no caller can share or mutate another's params.
function M.transition_params()
    return { menu_state_name = "overview", menu_sub_state_name = "forge" }
end

return M
