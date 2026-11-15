-- WP-CWV-02 (audit finding A2-F02): Character Weapon Variants and Weapons of
-- Chaos must not be switchable off from the VMF options menu. Disabling turns
-- every hook off while their items, lookup rows and vanilla table edits stay
-- (vmf/scripts/mods/vmf/modules/core/toggling.lua:9-25), which reopens the
-- crash classes of #278, #423 and #491. Loads each real data file under a stub
-- (pattern: test_woc_data_widgets.lua) and reads the returned flag.
return function(H, repo_root)
    local function load_data(folder, data_relative)
        local env
        local stub_mod = {
            localize = function(_, key) return "loc:" .. tostring(key) end,
            get = function() return nil end,
            dofile = function(_, script_path)
                local chunk = assert(loadfile(repo_root .. "/" .. folder .. "/" .. script_path .. ".lua"))
                setfenv(chunk, env)
                return chunk()
            end,
        }
        env = setmetatable({
            get_mod = function() return stub_mod end,
            mod = stub_mod,
        }, { __index = _G })
        local chunk = assert(loadfile(repo_root .. "/" .. folder .. "/" .. data_relative))
        setfenv(chunk, env)
        return chunk()
    end

    H.test("CWV A2-F02 data file declares the mod non-togglable", function()
        local data = load_data("character_weapon_variants",
            "scripts/mods/character_weapon_variants/character_weapon_variants_data.lua")
        H.equal(type(data), "table")
        H.equal(data.is_togglable, false)
    end)

    H.test("WOC A2-F02 data file declares the mod non-togglable", function()
        local data = load_data("weapons_of_chaos",
            "scripts/mods/weapons_of_chaos/weapons_of_chaos_data.lua")
        H.equal(type(data), "table")
        H.equal(data.is_togglable, false)
    end)
end
