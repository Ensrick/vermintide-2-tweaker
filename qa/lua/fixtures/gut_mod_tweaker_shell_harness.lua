-- Actual menu-shell entry/child harness; engine collaborators alone are fakes.
-- Owned by: test_gut_mod_tweaker_keep_routing.lua's registered behavioral cases.
-- Consumed via: a private factory, with no host globals or package mutation.
return function(repo_root)
    local base = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local function read(path)
        local f = assert(io.open(path, "rb"), "required menu-shell source absent: " .. path)
        local s = f:read("*a"); f:close()
        return (s:gsub("\r\n", "\n"))
    end
    local main = read(base .. "gui_tweaker_dev.lua")
    local owner_path = base .. "_gut_mod_tweaker_shell.lua"
    local owner = read(owner_path)
    local first = assert(main:find("-- #2: closed native-menu shell;", 1, true))
    local last = assert(main:find('mod:dofile("scripts/mods/gui_tweaker_dev/_gut_mod_tweaker_contracts").install({', first, true))
    local tail_end = assert(main:find('_gut_la_keepalive = mod:dofile("scripts/mods/gui_tweaker_dev/_la_atlas_keepalive")', last, true))
    tail_end = assert(main:find("\n", tail_end, true))
    local tail = main:sub(last, tail_end)
    local current = main:sub(first, last - 1)
    local prior_path = repo_root .. "/qa/lua/fixtures/gut_mod_tweaker_shell_gui365.lua"
    local prior = read(prior_path) -- Mandatory portable oracle, never an external-context SKIP.
    local prior_end = "-- End of exact published menu-shell payload.\n"
    assert(prior:sub(-#prior_end) == prior_end, "required historical payload trailer absent")
    prior = prior:sub(1, -#prior_end - 1) -- Restore the exact captured bytes before execution.

    local function build(opts)
        opts = opts or {}
        local f = { ledger = {}, logs = {}, hooks = {}, commands = {}, help = {}, checks = {},
            lookup = {}, source_reads = {}, pin_calls = 0, view_calls = 0, loc_calls = 0 }
        local function event(s) f.ledger[#f.ledger + 1] = s end
        local function log(kind, fmt, ...)
            local s = select("#", ...) == 0 and tostring(fmt) or string.format(fmt, ...)
            f.logs[#f.logs + 1] = { kind, s }
        end
        f.dbg = function(...) log("dbg", ...) end
        f.alert = function(...) log("alert", ...) end
        f.localization = {}
        for _, key in ipairs({ "gut_hidden_passive_whc_headshot_name", "gut_hidden_passive_whc_headshot_desc",
            "gut_hidden_passive_whc_crit_name", "gut_hidden_passive_whc_crit_desc",
            "gut_hidden_passive_whc_combined_name", "gut_hidden_passive_whc_combined_desc",
            "gut_video_profiles_header", "gut_video_profile_selector", "gut_video_profile_selector_tooltip",
            "gut_video_profile_action", "gut_video_profile_action_tooltip" }) do
            f.localization[key] = { en = key .. " 25%%" }
        end
        if opts.incomplete then f.localization.gut_video_profile_action_tooltip = nil end
        f.keepalive = {
            is_pinned = function() event("la:is_pinned"); return true end,
            pin = function() f.pin_calls = f.pin_calls + 1; event("la:pin") end,
        }
        f.api = {
            install = function(dbg, alert)
                assert(dbg == f.dbg and alert == f.alert, "actual API collaborator identity changed")
                event("api:install")
                if opts.install_error then error(opts.install_error, 0) end
                return opts.install_result
            end,
            is_registered = function(_, key)
                event("api:registered:" .. key)
                if opts.registry_error then error(opts.registry_error, 0) end
                return opts.registered
            end,
            register_category = function(_, row) event("api:category:" .. row.mod_id); f.category = row end,
        }
        f.mod = {
            hook_safe = function(_, class, method, callback)
                local key = class .. "." .. method
                assert(not f.hooks[key], "duplicate actual hook: " .. key)
                event("hook:" .. key); f.hooks[key] = callback
            end,
            command = function(_, name, help, callback)
                event("command:" .. name); f.commands[name] = callback; f.help[name] = help
            end,
            debug = function(_, ...) log("debug", ...) end,
            warning = function(_, ...) log("warning", ...) end,
            echo = function(_, ...) log("echo", ...) end,
            info = function(_, ...) log("info", ...) end,
        }
        f.settings = { transitions = opts.transitions or {} }
        local localizer = { append_backend_localizations = function(_, strings)
            event(strings.mod_tweaker_button_name and "loc:button" or "loc:keys")
            for k, v in pairs(strings) do f.lookup[k] = v end
        end }
        f.env = setmetatable({ package = { loaded = {} }, Managers = {
            localizer = not opts.no_localizer and localizer or nil,
            package = { has_loaded = function() event("la:resident"); return true end },
        }, printf = function() event("printf") end }, { __index = _G })
        f.env._G = f.env
        f.env.Localize = function(k) return f.lookup[k] or "<" .. k .. ">" end
        if not opts.no_settings then
            f.env.package.loaded["scripts/ui/views/ingame_ui_settings"] = f.settings
        end
        f.env.HeroViewStateModTweaker = {}
        f.mod.on_setting_changed = assert(loadstring("return function() end", "@" .. base .. "gui_tweaker_dev.lua"))()
        f.sources = { [base .. "gui_tweaker_dev.lua"] = main, [owner_path] = owner }
        if opts.owner_source then f.sources[owner_path] = opts.owner_source(owner) end
        local function chunk(source, path)
            local fn = assert(loadstring(source, "@" .. path)); setfenv(fn, f.env)
            return fn()
        end
        f.env.get_mod = function() return f.mod end
        local function source_read(path)
            f.source_reads[#f.source_reads + 1] = path
            return f.sources[path]
        end
        local function register(name, fn)
            event("check:" .. name); f.checks[name] = fn
            if name == "issue153_292_engine_ui_loc_supplied" and opts.register_error then
                error(opts.register_error, 0)
            end
        end
        f.mod.dofile = function(_, path)
            local name = assert(path:match("([^/]+)$"))
            event("load:" .. name)
            if name == "_gut_mod_tweaker_shell" then
                local M = chunk(f.sources[owner_path], owner_path)
                return { bind = function(config)
                    f.config = config
                    local bound = M.bind(config)
                    f.bound = bound
                    if opts.after_bind then opts.after_bind(f, config) end
                    local decorated = {}
                    for _, phase in ipairs({ "install_api", "install_routing", "install_compaction" }) do
                        local real = bound[phase]
                        decorated[phase] = function(...)
                            event("phase:" .. phase)
                            return real(...)
                        end
                    end
                    return decorated
                end }
            elseif name == "_mod_tweaker" then
                if opts.api_error then error(opts.api_error, 0) end
                if opts.api_non_table then return false end
                return f.api
            elseif name == "_mod_tweaker_view" then
                f.view_calls = f.view_calls + 1
                if opts.view_load_error then error(opts.view_load_error, 0) end
                if opts.view_non_table then return false end
                return { new = function(_, ctx)
                    event("view:new"); f.view_context = ctx
                    if opts.view_new_error then error(opts.view_new_error, 0) end
                    if opts.view_false then return false end
                    if opts.view_nil then return nil end
                    return opts.view_result or { value = "actual-view-constructor-result" }
                end }
            elseif name == "gui_tweaker_dev_localization" then
                f.loc_calls = f.loc_calls + 1
                if opts.loc_error then error(opts.loc_error, 0) end
                return f.localization
            elseif name == "_gut_dx12_fence630" then
                return { new = function(config) event("dx12:new"); f.probe = config; return { probe = true } end }
            elseif name == "_gut_mod_tweaker_contracts" then
                return chunk(read(base .. name .. ".lua"), base .. name .. ".lua")
            elseif name == "_gut_dialogue_contract" then
                return { install = function() end }
            elseif name == "_mod_tweaker_tab_labels" then
                return { rt_checks = {} }
            elseif name == "_gut_ui_tweaks_integration" then
                return { install = function() event("ui:install"); return {} end }
            elseif name == "_la_atlas_keepalive" then
                return f.keepalive
            elseif name == "_gut_config_file" then
                if opts.before_la then opts.before_la(f) end
                return { read_supported = false, export_to_log = function() end }
            end
            return {}
        end
        local span = opts.old and prior or current
        local fn = assert(loadstring("local mod, _dbg, _dbg_alert, _rt_register, _rt_src_read = ...\n"
            .. span .. tail .. "\nreturn { keys = ENGINE_UI_LOC_KEYS, harvest = _engine_ui_localizations }\n",
            "@" .. (opts.old and prior_path or base .. "gui_tweaker_dev.lua")))
        setfenv(fn, f.env)
        f.private = fn(f.mod, f.dbg, f.alert, register, source_read)
        local error_source = opts.old and prior or f.sources[owner_path]
        local at = assert(error_source:find('error("ingame_ui_settings not in package.loaded;', 1, true))
        local line = select(2, error_source:sub(1, at):gsub("\n", "")) + 1 + (opts.old and 1 or 0)
        local info = debug.getinfo(opts.old and fn or f.bound.install_routing, "S")
        f.settings_error_prefix = "[mt] transitions injection failed: " .. info.short_src .. ":" .. line .. ": "
        return f
    end

    local function normalized_ledger(f)
        local t = {}
        for _, value in ipairs(f.ledger) do
            if value ~= "load:_gut_mod_tweaker_shell" and not value:find("phase:", 1, true) then
                t[#t + 1] = value
            end
        end
        return t
    end
    local function ui(origin, ctx)
        return { views = {}, current_view = origin, ingame_ui_context = ctx or { ui_renderer = "renderer" } }
    end
    local function snapshot(t)
        local row = { meta = getmetatable(t), fields = {} }
        for k, v in next, t do row.fields[k] = v end
        return row
    end
    local function unchanged(t, row)
        if getmetatable(t) ~= row.meta then return false end
        for k, v in next, t do if rawget(row.fields, k) ~= v then return false end end
        for k, v in next, row.fields do if rawget(t, k) ~= v then return false end end
        return true
    end
    return { build = build, ledger = normalized_ledger, ui = ui, read = read,
        snapshot = snapshot, unchanged = unchanged, owner_path = owner_path }
end
