return function(H, repo_root)
    local retired = {
        "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_big_rebalance.lua",
        "/enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker_big_rebalance.lua",
        "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_big_rebalance.lua",
        "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker_big_rebalance_defs.lua",
        "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_big_rebalance.lua",
        "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_big_rebalance_defs.lua",
    }
    local entry_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker.lua"
    local data_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_data.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end

    H.test("retired Big Rebalance implementations are absent from shipped scripts", function()
        for i = 1, #retired do
            local file = io.open(repo_root .. retired[i], "rb")
            if file then file:close() end
            H.equal(file, nil, retired[i] .. " must remain recoverable from git only")
        end
    end)

    H.test("CRT retired Big Rebalance has no executable lifecycle stub", function()
        local source = read(entry_path)
        -- Remove line comments before checking executable text. The retirement
        -- explanation itself is expected to name Big Rebalance.
        source = source:gsub("%-%-[^\r\n]*", "")
        H.equal(source:find("big_rebalance", 1, true), nil)
        H.equal(source:find('setting_id:find("^cbr_")', 1, true), nil)
    end)

    H.test("CRT cleanup preserves live native and Tourney family surfaces", function()
        local data = read(data_path)
        H.truthy(data:find('setting_id = "rework_master_ensrick"', 1, true))
        H.truthy(data:find('setting_id = "rework_master_tourney"', 1, true))
        H.truthy(data:find('cb("trn_es_mercenary")', 1, true))
        H.truthy(data:find('setting_id = "rework_general_stagger_thp"', 1, true))
    end)

    H.test("WT and ET retain no executable retired lifecycle plumbing", function()
        local paths = {
            "/weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua",
            "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/weapon_tweaker_dev.lua",
            "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_fingerprint.lua",
            "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_lifecycle.lua",
        }
        for i = 1, #paths do
            local source = read(repo_root .. paths[i]):gsub("%-%-[^\r\n]*", "")
            H.equal(source:find("big_rebalance", 1, true), nil, paths[i])
            H.equal(source:find("BR.on_", 1, true), nil, paths[i])
        end
        local fingerprint = read(repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_fingerprint.lua")
        H.truthy(fingerprint:find("ET.settings_fingerprint = _settings_fingerprint", 1, true),
            "universal ET settings fingerprint must survive BR RPC removal")
        H.equal(fingerprint:find('network_register("et_br_fingerprint"', 1, true), nil)
    end)
end
