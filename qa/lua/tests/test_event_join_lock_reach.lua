-- WP-CW-01 (#430, #413): the Events curse join lock must reach the live
-- game-mode instance. Vanilla class() copies parent methods into the child
-- table at definition time (foundation/scripts/util/class.lua:50-56), so a
-- hook on GameModeBase.is_joinable never runs for a GameModeAdventure
-- instance. This suite models that copy and proves the lock is installed on
-- the derived classes the engine actually instantiates.
return function(H, repo_root)
    local policy_path = repo_root
        .. "/event_tweaker/scripts/mods/event_tweaker/event_tweaker_curse_join_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    local DERIVED = { "GameModeAdventure", "GameModeDeus", "GameModeMapDeus", "GameModeWeave" }

    -- Copy-at-definition class model, like vanilla class().
    local function class(parent)
        local c = {}
        c.__index = c
        for k, v in pairs(parent or {}) do
            if k ~= "__index" then
                c[k] = v
            end
        end
        return c
    end

    local function new_env()
        local env = {}
        env.GameModeBase = class()
        env.GameModeBase.is_joinable = function() return true end
        for _, name in ipairs(DERIVED) do
            env[name] = class(env.GameModeBase)
        end
        return env
    end

    local function hook_for(env)
        return function(class_name, method, handler)
            local t = env[class_name]
            local orig = t[method]
            t[method] = function(self, ...)
                return handler(orig, self, ...)
            end
        end
    end

    H.test("Event Tweaker join lock targets exactly the four live game-mode classes", function()
        local classes = Policy.JOIN_LOCK_CLASSES
        H.truthy(type(classes) == "table", "JOIN_LOCK_CLASSES must be a table")
        H.equal(#classes, 4)
        local seen = {}
        for _, name in ipairs(classes) do
            seen[name] = true
        end
        for _, name in ipairs(DERIVED) do
            H.truthy(seen[name], "missing join lock class " .. name)
        end
        H.equal(seen.GameModeBase, nil, "the lock must not target GameModeBase")
    end)

    H.test("Event Tweaker join lock reaches derived game-mode instances", function()
        local env = new_env()
        local locked = false
        H.truthy(type(Policy.install_join_lock) == "function", "install_join_lock must exist")
        local requested = Policy.install_join_lock(hook_for(env), function() return locked end)
        H.equal(requested, 4)
        for _, name in ipairs(DERIVED) do
            local instance = setmetatable({}, env[name])
            locked = true
            H.equal(instance:is_joinable(), false, name .. " must refuse joins while locked")
            locked = false
            H.equal(instance:is_joinable(), true, name .. " must stay joinable while open")
        end
    end)

    H.test("Control: a GameModeBase hook never reaches a GameModeAdventure instance", function()
        local env = new_env()
        hook_for(env)("GameModeBase", "is_joinable", function(func, self, ...)
            return Policy.allow_join(func(self, ...), true)
        end)
        H.equal(setmetatable({}, env.GameModeBase):is_joinable(), false)
        H.equal(setmetatable({}, env.GameModeAdventure):is_joinable(), true)
    end)
end
