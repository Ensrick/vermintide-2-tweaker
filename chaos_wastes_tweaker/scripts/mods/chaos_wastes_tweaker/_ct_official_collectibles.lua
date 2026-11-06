--[[
_ct_official_collectibles - counter-only closed #533 dependency for #571.
Derived from _ct_tab_panel_owner in Dev tree a179354e; no boon previews,
native diagnostic capture, tooltip/input ownership, custom RPC or wire rows.
Owns only previously-unowned IngamePlayerListUI._setup_mission_data/_draw.
Owned by: chaos_wastes_tweaker.lua. Consumed via: mod:dofile.
]]
local mod = get_mod("ct")
local M = {}
local CT_CW_TAB_COLLECTIBLES_533_MARKER = "cw_tab_collectibles_deus_counters_v0.7.257"
do
    -- Live deus run controller or nil (stock Adventure / keep -> nil). Correct on every
    -- peer: only the deus mechanism exposes get_deus_run_controller.
    local function deus_run_controller_or_nil()
        local mm = Managers.mechanism
        local mech = mm and mm.game_mechanism and mm:game_mechanism()
        return (mech and mech.get_deus_run_controller and mech:get_deus_run_controller()) or nil
    end

    -- The two deus counter rows (order = display order, top to bottom).
    local ROWS = {
        { key = "chests", icon = "deus_icons_boon", label_key = "ct_tab_chests_of_trials" },
        { key = "coins",  icon = "deus_icons_coin", label_key = "ct_tab_pilgrims_coins" },
    }
    -- Native-sized; #571 reuses vanilla's widget-local two-per-row offset loop.
    local ICON_SIZE = 80

    -- Verbatim copy of vanilla create_loot_widget (definitions:843-1041) MINUS the
    -- glow_icon pass/style: `texture .. "_glow"` does not exist for the deus icons and
    -- a missing atlas texture would kill the draw. Everything else (amount-gated lit
    -- icon over a black silhouette, title bottom-right of the icon, counter above it)
    -- is vanilla's own layout so the pane matches the adventure counters it replaces.
    local function create_deus_loot_widget(texture, text, scale)
        local texture_settings = UIAtlasHelper.get_atlas_settings_by_texture_name(texture)
        local texture_size = texture_settings.size
        scale = scale or 1
        return {
            scenegraph_id = "loot_objective",
            element = {
                passes = {
                    { pass_type = "text", style_id = "text", text_id = "text" },
                    { pass_type = "text", style_id = "text_shadow", text_id = "text" },
                    {
                        pass_type = "text", style_id = "counter_text", text_id = "counter_text",
                        content_check_function = function(content) return content.amount > 0 end,
                    },
                    {
                        pass_type = "text", style_id = "counter_text_disabled", text_id = "counter_text",
                        content_check_function = function(content) return content.amount == 0 end,
                    },
                    { pass_type = "text", style_id = "counter_text_shadow", text_id = "counter_text" },
                    {
                        pass_type = "texture", style_id = "icon", texture_id = "icon",
                        content_check_function = function(content) return content.amount > 0 end,
                    },
                    { pass_type = "texture", style_id = "background_icon", texture_id = "icon" },
                },
            },
            content = {
                amount = 0,
                counter_text = "x0",
                text = text or "n/a",
                icon = texture,
            },
            style = {
                text = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "bottom",
                    text_color = Colors.get_table("font_title"),
                    offset = { scale * texture_size[1], scale * texture_size[2] - 50, 1 },
                },
                text_shadow = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "bottom",
                    text_color = Colors.get_table("black"),
                    offset = { scale * texture_size[1] + 1, scale * texture_size[2] - 50 - 1, 0 },
                },
                counter_text = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "top",
                    text_color = Colors.get_table("font_default"),
                    offset = { scale * texture_size[1], -40, 1 },
                },
                counter_text_disabled = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "top",
                    text_color = { 255, 130, 130, 130 },
                    offset = { scale * texture_size[1], -40, 1 },
                },
                counter_text_shadow = {
                    font_size = 32, font_type = "hell_shark_header",
                    horizontal_alignment = "left", vertical_alignment = "top",
                    text_color = Colors.get_table("black"),
                    offset = { scale * texture_size[1] + 1, -41, 0 },
                },
                icon = {
                    horizontal_alignment = "left", vertical_alignment = "top",
                    color = { 255, 255, 255, 255 },
                    offset = { 0, 0, 1 },
                    texture_size = { scale * texture_size[1], scale * texture_size[2] },
                },
                background_icon = {
                    horizontal_alignment = "left", vertical_alignment = "top",
                    color = { 255, 0, 0, 0 },
                    offset = { 0, 0, 0 },
                    texture_size = { scale * texture_size[1], scale * texture_size[2] },
                },
            },
            offset = { 0, 0, 0 },
        }
    end

    -- Own-peer chest/coin values, or nil outside a deus run. Exposed on mod for the
    -- regression check and any future /verify surface.
    function mod._ct_read_deus_collectible_values()
        local dc = deus_run_controller_or_nil()
        if not dc then return nil end
        local peer = dc.get_own_peer_id and dc:get_own_peer_id()
        if not peer then return nil end
        local chests = (dc.get_cursed_chests_purified and dc:get_cursed_chests_purified(peer)) or 0
        local coins = (dc.get_player_soft_currency and dc:get_player_soft_currency(peer)) or 0
        return {
            chests = math.floor((tonumber(chests) or 0) + 0.5),
            coins = math.floor(tonumber(coins) or 0),  -- HUD indicator floors too (:78)
        }
    end

    -- Build once; live placement happens after the scenegraph resolves below.
    function mod._ct_build_deus_collectibles()
        local rows = {}
        for i, spec in ipairs(ROWS) do
            local title = mod:localize(spec.label_key)
            local widget = UIWidget.init(create_deus_loot_widget(spec.icon, title, 1))
            rows[#rows + 1] = { key = spec.key, title = title, widget = widget, last = nil }
        end
        return { rows = rows, layout_signature = nil }
    end

    -- Per-frame value refresh while the panel draws (called from the shared _draw hook
    -- above). Mirrors vanilla _sync_missions: only rewrite content when the value
    -- changed (ingame_player_list_ui_v2.lua:530-543).
    function mod._ct_refresh_deus_collectibles(self)
        local cw = self._ct_deus_collectibles
        if not cw then return end
        local values = mod._ct_read_deus_collectible_values()
        if not values then return end
        for _, row in ipairs(cw.rows) do
            local v = values[row.key] or 0
            if v ~= row.last then
                row.last = v
                local content = row.widget.content
                content.amount = v
                content.counter_text = "x" .. tostring(v)
            end
        end
    end
    -- Build point + adventure-counter suppression. FULL wrapper (not hook_safe): under
    -- the deus mechanism vanilla must NOT run -- it would build tome/grim/dice counters
    -- from the injected level's defaulted loot_objectives. Keep/hubs stay vanilla.
    mod:hook("IngamePlayerListUI", "_setup_mission_data", function(func, self, level_settings)
        self._ct_deus_collectibles = nil
        self._ct_deus_collectibles_build_failed = nil
        if self._is_in_inn or (level_settings and level_settings.hub_level)
            or not deus_run_controller_or_nil() then
            return func(self, level_settings)
        end
        if not mod._ct_ensure_deus_collectibles(self, "setup_mission_data") then
            return func(self, level_settings)
        end
        -- Deliberately NOT calling func: on a deus-run level the vanilla build is either
        -- a no-op (vanilla CW level, no loot_objectives) or wrong (injected adventure
        -- level, defaulted adventure loot_objectives).
    end)
end

local layout = mod:dofile("scripts/mods/chaos_wastes_tweaker/_ct_tab_collectibles_layout")

-- Sole official draw hook. Vanilla has closed its own renderer pass here.
-- resource-safety: ct_public_collectibles_native_gui
-- Exact native PlayerList top-Gui route/lifetime; test_ct_official_native_gui_contract.
mod:hook_safe("IngamePlayerListUI", "_draw", function(self, dt)
    if not self._ct_deus_collectibles then
        pcall(mod._ct_ensure_deus_collectibles, self, "draw_recovery")
    end
    local cw = self._ct_deus_collectibles
    if not cw then return end
    pcall(function()
        local renderer, scenegraph = self._ui_top_renderer, self._ui_scenegraph
        local input_manager = self._input_manager
        local input_service = input_manager and input_manager:get_service("player_list_input")
        local settings = self._render_settings
        if not (renderer and scenegraph and input_service and settings) then return end
        pcall(mod._ct_layout_deus_collectibles, self)
        pcall(mod._ct_refresh_deus_collectibles, self)
        UIRenderer.begin_pass(renderer, scenegraph, input_service, dt, nil, settings)
        if self._collectibles_name then pcall(UIRenderer.draw_widget, renderer, self._collectibles_name) end
        if self._collectibles_divider then pcall(UIRenderer.draw_widget, renderer, self._collectibles_divider) end
        for i = 1, #cw.rows do
            pcall(UIRenderer.draw_widget, renderer, cw.rows[i].widget)
        end
        UIRenderer.end_pass(renderer)
    end)
end)

M.rt_checks = {
    { "issue533_cw_tab_collectibles_wired", function()
        if CT_CW_TAB_COLLECTIBLES_533_MARKER ~= "cw_tab_collectibles_deus_counters_v0.7.257"
            or type(mod._ct_build_deus_collectibles) ~= "function"
            or type(mod._ct_refresh_deus_collectibles) ~= "function"
            or type(mod._ct_read_deus_collectible_values) ~= "function" then
            return "#533 required collectible counter helpers missing"
        end
        local value = mod._ct_read_deus_collectible_values()
        if value ~= nil and (type(value) ~= "table"
            or type(value.chests) ~= "number" or type(value.coins) ~= "number") then
            return "#533 collectible value reader contract broken"
        end
    end },
    { "issue571_cw_tab_collectibles_safe_reflow", layout.regression },
}
return M
