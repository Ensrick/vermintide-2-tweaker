-- WP-WT-08: mod:safe_hook must never run the hooked original twice. Handlers
-- that call the original first and fail afterwards (for example the
-- GearUtils.spawn_inventory_unit wrapper) used to make the fallback call the
-- original a second time. Loads the production _safe_hook.lua of both trees.

return function(H, repo_root)
    local trees = {
        { name = "wt", mod_name = "wt", path = repo_root
            .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_safe_hook.lua" },
        { name = "wt_dev", mod_name = "wt_dev", path = repo_root
            .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_safe_hook.lua" },
    }

    local function load_tree(tree)
        local log = { errors = {}, swallowed = {} }
        local wrappers = {}
        local mod = {
            _wt = {
                note_swallowed = function(kind, detail)
                    log.swallowed[#log.swallowed + 1] = kind .. ":" .. tostring(detail)
                end,
            },
        }
        function mod.hook(_, class, method, wrapper) wrappers[class .. "." .. method] = wrapper end
        function mod.error(_, fmt, ...) log.errors[#log.errors + 1] = string.format(fmt, ...) end
        function mod.info() end
        function mod.debug() end
        local env = setmetatable({
            get_mod = function(name)
                if name == tree.mod_name then return mod end
                return nil
            end,
        }, { __index = _G })
        local chunk = assert(loadfile(tree.path))
        setfenv(chunk, env)
        chunk()
        H.equal(type(mod.safe_hook), "function", "safe_hook not attached")
        return mod, wrappers, log
    end

    local function counting_original(raise)
        local counter = { calls = 0 }
        counter.fn = function()
            counter.calls = counter.calls + 1
            if raise then error("original boom") end
            return 1, nil, 3, nil
        end
        return counter
    end

    local function pack(...) return { n = select("#", ...), ... } end

    local function wrap(mod, wrappers, handler)
        mod:safe_hook("Probe", "method", handler)
        return assert(wrappers["Probe.method"], "wrapper not registered")
    end

    local function assert_four(values)
        H.equal(values.n, 4, "lost a return value or nil hole")
        H.equal(values[1], 1); H.equal(values[2], nil); H.equal(values[3], 3); H.equal(values[4], nil)
    end

    for _, tree in ipairs(trees) do
        H.test(tree.name .. " safe_hook (a) pass-through calls the original once with nil holes", function()
            local mod, wrappers, log = load_tree(tree)
            local original = counting_original(false)
            local wrapper = wrap(mod, wrappers, function(func, ...) return func(...) end)
            assert_four(pack(wrapper(original.fn, "a", nil, "c")))
            H.equal(original.calls, 1)
            H.equal(#log.errors, 0)
            H.equal(#log.swallowed, 0)
        end)

        H.test(tree.name .. " safe_hook (b) a raise after the original does not call it again", function()
            local mod, wrappers, log = load_tree(tree)
            local original = counting_original(false)
            local wrapper = wrap(mod, wrappers, function(func, ...)
                func(...)
                error("late boom")
            end)
            assert_four(pack(wrapper(original.fn, "a", nil, "c")))
            H.equal(original.calls, 1, "original ran twice")
            H.equal(#log.errors, 1)
            H.truthy(log.errors[1]:find("late boom", 1, true), "error line lost the message")
            H.deep_equal(log.swallowed, { "safe_hook:Probe.method" })
        end)

        H.test(tree.name .. " safe_hook (c) a raise before the original falls back once", function()
            local mod, wrappers, log = load_tree(tree)
            local original = counting_original(false)
            local wrapper = wrap(mod, wrappers, function() error("early boom") end)
            assert_four(pack(wrapper(original.fn, "a", nil, "c")))
            H.equal(original.calls, 1)
            H.equal(#log.errors, 1)
        end)

        H.test(tree.name .. " safe_hook (d) an original that raises runs once and propagates", function()
            local mod, wrappers = load_tree(tree)
            local original = counting_original(true)
            local wrapper = wrap(mod, wrappers, function(func, ...) return func(...) end)
            local ok, err = pcall(wrapper, original.fn, "a", nil, "c")
            H.equal(ok, false, "the original's error must reach the caller")
            H.truthy(tostring(err):find("original boom", 1, true), "lost the original error text")
            H.equal(original.calls, 1, "original ran twice")
        end)
    end
end
