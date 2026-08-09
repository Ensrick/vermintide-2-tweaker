return function(_H, repo_root)
    local function read(file) local h = assert(io.open(file, "rb")); local value = h:read("*a"); h:close(); return value end
    local function occurrences(value, needle) local n, cursor = 0, 1; while true do local found = value:find(needle, cursor, true); if not found then return n end; n, cursor = n + 1, found + #needle end end
    local separator = package.config:sub(1, 1)
    local function path(relative) return repo_root .. separator .. relative:gsub("/", separator) end
    local entry_path = path("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    local module_path = path("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_news_feed_safety.lua")
    local entry_source = read(entry_path)
    local module_source = read(module_path)
    local owner_dofile = 'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_news_feed_safety")'
    assert(occurrences(entry_source, owner_dofile) == 1, "entry must install news-feed owner exactly once")
    assert(not entry_source:find("local _hot_reload_purges", 1, true), "entry must not retain purge state")
    assert(not entry_source:find('mod:hook_origin("NewsFeedUI", "draw"', 1, true), "entry must not retain draw hook")
    assert(entry_source:find(owner_dofile, 1, true) < entry_source:find('mod:dofile("scripts/mods/cosmetics_tweaker/_cos_mod_lifecycle")', 1, true), "owner order drifted")
    assert(occurrences(module_source, 'mod:hook_origin("NewsFeedUI", "draw"') == 1, "owner must register one origin hook")
    assert(module_source:find("Owned by:", 1, true) and module_source:find("Consumed via:", 1, true), "owner header incomplete")
    assert(not module_source:find("network_register", 1, true) and not module_source:find("network_send", 1, true), "owner must remain network-free")
    local hook_count, callback = 0, nil
    local mod = {}
    function mod:hook_origin(class_name, method_name, fn) assert(class_name == "NewsFeedUI" and method_name == "draw"); hook_count, callback = hook_count + 1, fn end
    local a_calls, a_logs = 0, 0
    local renderer_a = { begin_pass = function() a_calls = a_calls + 1 end, draw_widget = function() a_calls = a_calls + 1 end, end_pass = function() a_calls = a_calls + 1 end }
    local b_calls, b_logs = {}, {}
    local renderer_b = { begin_pass = function() b_calls[#b_calls + 1] = "begin" end, draw_widget = function(_, widget) b_calls[#b_calls + 1] = "draw:" .. widget.id; if widget.fail then error("missing material") end end, end_pass = function() b_calls[#b_calls + 1] = "end" end }
    local owner_a = assert(loadfile(module_path))().install(mod, { dbg_alert = function() a_logs = a_logs + 1 end, get_ui_renderer = function() return renderer_a end })
    assert(owner_a == mod._cos_news_feed_safety_owner and owner_a.hook_count == 1 and hook_count == 1, "first install shape/cardinality drifted")
    local replacement_owner = { stale = true }; mod._cos_news_feed_safety_owner = replacement_owner
    local owner_b = assert(loadfile(module_path))().install(mod, { dbg_alert = function(format, ...) b_logs[#b_logs + 1] = string.format(format, ...) end, get_ui_renderer = function() return renderer_b end })
    assert(hook_count == 1 and owner_b == replacement_owner and owner_b.stale == nil and owner_b.hook_count == 1, "reload must refresh exact owner without duplicate hook")
    local good, bad = { id = "good" }, { id = "bad", fail = true }
    local view = { ui_renderer = {}, ui_scenegraph = {}, input_manager = { get_service = function(_, name) assert(name == "ingame_menu"); return {} end }, _active_news = { { widget = good }, { widget = bad } }, _unused_news_widgets = {} }
    callback(view, 0.25)
    assert(a_calls == 0 and a_logs == 0, "callback must consume refreshed action-time dependencies")
    assert(table.concat(b_calls, ",") == "begin,draw:good,draw:bad,end", "renderer pass/order drifted")
    assert(#view._active_news == 1 and view._active_news[1].widget == good, "healthy widget order/purge drifted")
    assert(#view._unused_news_widgets == 1 and view._unused_news_widgets[1] == bad, "failed widget was not recycled")
    assert(#b_logs == 1 and b_logs[1]:find("missing material", 1, true), "refreshed logger did not report failure")
    for i = 1, 5 do view._active_news = { { widget = { id = "bad" .. i, fail = true } } }; callback(view, i) end
    assert(#b_logs == 5, "diagnostics must retain the historical five-purge threshold")
    assert(mod._cos_news_feed_safety_state.hot_reload_purges == 6, "all purges must remain counted")
end
