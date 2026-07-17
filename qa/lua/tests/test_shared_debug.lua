local function read(path)
    local file = assert(io.open(path, "rb"))
    local content = file:read("*a")
    file:close()
    return content
end

return function(H, repo_root)
    local canonical_path = repo_root .. "/tools/shared_lib/_lib_debug.lua"
    local consumers = {
        {
            copy = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_lib_debug.lua",
            entry = repo_root .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua",
            load = 'mod:dofile("scripts/mods/crafting_in_modded_dev/_lib_debug")(mod, "[cim:dbg]")',
        },
        {
            copy = repo_root .. "/verminious_dreams_lighting_dev/scripts/mods/verminious_dreams_lighting_dev/_lib_debug.lua",
            entry = repo_root .. "/verminious_dreams_lighting_dev/scripts/mods/verminious_dreams_lighting_dev/verminious_dreams_lighting_dev.lua",
            load = 'mod:dofile("scripts/mods/verminious_dreams_lighting_dev/_lib_debug")(mod, "[vdl:dbg]")',
        },
    }

    H.test("shared debug helper preserves gated and log-only channels", function()
        local debug_calls, printf_calls = {}, {}
        local old_printf = _G.printf
        _G.printf = function(...)
            printf_calls[#printf_calls + 1] = { ... }
        end

        local factory = assert(loadfile(canonical_path))()
        local dbg, alert = factory({
            debug = function(_, ...)
                debug_calls[#debug_calls + 1] = { ... }
            end,
        }, "[probe]")
        dbg("value=%d", 7)
        alert("bad=%s", "x")
        _G.printf = old_printf

        H.equal(debug_calls[1][1], "[probe] value=%d")
        H.equal(debug_calls[1][2], 7)
        H.equal(printf_calls[1][1], "[probe] bad=%s")
        H.equal(printf_calls[1][2], "x")
    end)

    H.test("CIM and VDL own exact standalone debug copies", function()
        local canonical = read(canonical_path)
        local manifest = read(repo_root .. "/tools/shared_lib/manifest.psd1")
        for _, consumer in ipairs(consumers) do
            H.equal(read(consumer.copy), canonical, "consumer drifted from canonical helper")
            local relative = consumer.copy:sub(#repo_root + 2):gsub("\\", "/")
            H.truthy(manifest:find('"' .. relative .. '"', 1, true), "consumer missing from manifest")
            local entry = read(consumer.entry)
            H.truthy(entry:find(consumer.load, 1, true), "entry does not load its owned copy")
            H.equal(entry:find("local function _dbg", 1, true), nil, "inline helper still owns debug behavior")
        end
    end)
end
