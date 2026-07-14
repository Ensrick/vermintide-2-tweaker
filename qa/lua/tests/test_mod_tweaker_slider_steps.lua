return function(Harness, repo_root)
    local function read(path)
        local f = assert(io.open(repo_root .. "/" .. path, "rb"))
        local s = f:read("*a")
        f:close()
        return s
    end

    local files = {
        "gui_tweaker/scripts/mods/gui_tweaker/_mod_tweaker_view.lua",
        "gui_tweaker/scripts/mods/gui_tweaker/_mod_tweaker_state.lua",
        "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_view.lua",
        "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_state.lua",
    }

    Harness.test("all Mod Tweaker presentations own the 25-point foreign slider contract", function()
        for i = 1, #files do
            local s = read(files[i])
            Harness.truthy(s:match("base_power_level%s*=%s*25"), files[i])
            Harness.truthy(s:match("starting_coins%s*=%s*25"), files[i])
            Harness.truthy(s:find("_resolve_step(w, category and category.mod_id", 1, true), files[i])
        end
    end)

    Harness.test("stable no longer accepts VMF-invalid range third elements", function()
        for i = 1, 2 do
            local s = read(files[i])
            Harness.equal(s:find("range and range[3]", 1, true), nil, files[i])
        end
    end)
end
