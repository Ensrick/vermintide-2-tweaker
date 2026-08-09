-- _cos_news_feed_safety.lua — bounded NewsFeedUI draw-failure containment owner.
--
-- Owns the existing NewsFeedUI.draw replacement that keeps the renderer pass
-- balanced when a stale news widget references an unavailable GUI material.
-- Failed widgets are recycled only after the pass closes, and diagnostics retain
-- the historical five-purge threshold. The callback resolves UIRenderer through
-- an action-time getter and a persistent state holder so a module reload refreshes
-- dependencies without registering a second hook.
--
-- Owned by: cosmetics_tweaker.lua entry point.
-- Consumed via: one ordered mod:dofile installer call before mod lifecycle setup;
-- guarded by qa/lua/tests/test_cos_news_feed_safety.lua.

local NewsFeedSafety = {}

local function publish_owner(mod, state)
    local owner = mod._cos_news_feed_safety_owner
    if type(owner) ~= "table" then
        owner = {}
    end

    for key in pairs(owner) do
        owner[key] = nil
    end

    owner.hook_count = 1
    mod._cos_news_feed_safety_owner = owner
    state.owner = owner

    return owner
end

function NewsFeedSafety.install(mod, deps)
    deps = deps or {}

    local state = mod._cos_news_feed_safety_state
    if not state then
        state = {
            installed = false,
            hot_reload_purges = 0,
        }
        mod._cos_news_feed_safety_state = state
    end

    state.dbg_alert = assert(deps.dbg_alert, "dbg_alert is required")
    state.get_ui_renderer = assert(deps.get_ui_renderer, "get_ui_renderer is required")

    if state.installed then
        return publish_owner(mod, state)
    end

    mod:hook_origin("NewsFeedUI", "draw", function(self, dt)
        local UIRenderer = state.get_ui_renderer()
        local ui_renderer = self.ui_renderer
        local ui_scenegraph = self.ui_scenegraph
        local input_service = self.input_manager:get_service("ingame_menu")

        UIRenderer.begin_pass(ui_renderer, ui_scenegraph, input_service, dt)

        local active_news = self._active_news
        local stale_indices

        for i = 1, #active_news do
            local widget = active_news[i].widget
            if widget then
                local ok, err = pcall(UIRenderer.draw_widget, ui_renderer, widget)
                if not ok then
                    stale_indices = stale_indices or {}
                    stale_indices[#stale_indices + 1] = i
                    if state.hot_reload_purges < 5 then
                        state.dbg_alert(
                            "[hot-reload-safety] news widget %d draw failed: %s",
                            i,
                            tostring(err)
                        )
                    end
                end
            end
        end

        UIRenderer.end_pass(ui_renderer)

        if stale_indices then
            for j = #stale_indices, 1, -1 do
                local i = stale_indices[j]
                local data = active_news[i]
                local widget = data and data.widget
                table.remove(active_news, i)
                if widget and self._unused_news_widgets then
                    table.insert(self._unused_news_widgets, widget)
                end
            end

            state.hot_reload_purges = state.hot_reload_purges + #stale_indices
        end
    end)

    state.installed = true
    return publish_owner(mod, state)
end

return NewsFeedSafety
