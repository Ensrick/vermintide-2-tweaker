-- qa/integration/fake_vmf.lua (WP-T-03): the smallest VMF surface a mod's data modules touch when loaded here.
--
-- get_mod(id) returns a recorder with get, set, hook, hook_safe, hook_origin, command, dofile, echo, info, warning,
-- error, debug and localize. It records calls and simulates nothing: hooks never run, commands never run, get
-- returns what set stored (nil otherwise). mod:dofile(path) runs <repo>/<mod dir>/<path>.lua, where the mod
-- directory comes from the id -> folder map run.lua builds from tools/mod-inventory.psd1 (ModId and Dir).
-- Called as dofile(...)(repo_root, dirs_by_mod_id); returns get_mod and the call counts.
return function(repo, dirs)
    local mods, calls = {}, { hook = 0, hook_safe = 0, hook_origin = 0, command = 0, get = 0, set = 0, dofile = 0 }

    local function new_mod(id)
        local mod = { _id = id, _settings = {}, _hooks = {}, _commands = {} }
        function mod:get(key) calls.get = calls.get + 1; return self._settings[key] end
        function mod:set(key, value) calls.set = calls.set + 1; self._settings[key] = value end
        function mod:hook(class, method, fn) calls.hook = calls.hook + 1; self._hooks[#self._hooks + 1] = { class, method, fn } end
        function mod:hook_safe(class, method, fn) calls.hook_safe = calls.hook_safe + 1; self._hooks[#self._hooks + 1] = { class, method, fn, safe = true } end
        function mod:hook_origin(class, method, fn) calls.hook_origin = calls.hook_origin + 1; self._hooks[#self._hooks + 1] = { class, method, fn, origin = true } end
        function mod:command(name, _, fn) calls.command = calls.command + 1; self._commands[name] = fn end
        function mod:dofile(path)
            calls.dofile = calls.dofile + 1
            local dir = dirs[id]
            if not dir then error("fake VMF: no mod folder for mod id " .. tostring(id) .. " in tools/mod-inventory.psd1", 2) end
            local chunk, err = loadfile(repo .. "/" .. dir .. "/" .. path .. ".lua")
            if not chunk then error("fake VMF: " .. tostring(err), 2) end
            return chunk()
        end
        function mod:echo() end
        function mod:info() end
        function mod:warning() end
        function mod:error() end
        function mod:debug() end
        function mod:localize(key) return key end
        return mod
    end

    local function get_mod(id)
        mods[id] = mods[id] or new_mod(id)
        return mods[id]
    end
    return get_mod, calls
end
