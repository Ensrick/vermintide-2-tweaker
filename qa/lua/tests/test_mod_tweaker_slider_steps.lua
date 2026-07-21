return function(Harness, repo_root)
    local function read(path)
        local f = assert(io.open(repo_root .. "/" .. path, "rb"))
        local s = f:read("*a")
        f:close()
        return s
    end

    local stable_files = {
        "gui_tweaker/scripts/mods/gui_tweaker/_mod_tweaker_view.lua",
        "gui_tweaker/scripts/mods/gui_tweaker/_mod_tweaker_state.lua",
    }

    local dev_files = {
        "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_view.lua",
        "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_state.lua",
    }

    Harness.test("Mod Tweaker dev resolves foreign slider steps through the setting owner", function()
        for i = 1, #dev_files do
            local s = read(dev_files[i])
            Harness.truthy(s:match("base_power_level%s*=%s*25"), dev_files[i])
            Harness.truthy(s:match("starting_coins%s*=%s*25"), dev_files[i])
            Harness.truthy(s:find("local _, owner_mod_id = _owner(category, setting_id)", 1, true), dev_files[i])
            Harness.truthy(s:find("_resolve_step(w, owner_mod_id", 1, true), dev_files[i])
            Harness.equal(s:find("_resolve_step(w, category and category.mod_id", 1, true), nil, dev_files[i])
        end
    end)

    Harness.test("stable still owns the registered 25-point slider contracts", function()
        for i = 1, #stable_files do
            local s = read(stable_files[i])
            Harness.truthy(s:match("base_power_level%s*=%s*25"), stable_files[i])
            Harness.truthy(s:match("starting_coins%s*=%s*25"), stable_files[i])
        end
    end)

    Harness.test("stable no longer accepts VMF-invalid range third elements", function()
        for i = 1, 2 do
            local s = read(stable_files[i])
            Harness.equal(s:find("range and range[3]", 1, true), nil, stable_files[i])
        end
    end)
end
