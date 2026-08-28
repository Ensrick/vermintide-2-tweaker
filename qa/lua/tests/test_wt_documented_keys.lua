return function(H, repo_root)
    local stable_root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local dev_root = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count(table_value)
        local total = 0
        for _ in pairs(table_value) do
            total = total + 1
        end
        return total
    end

    local stable_keys = dofile(stable_root .. "wt_documented_keys.lua")
    local dev_keys = dofile(dev_root .. "wt_documented_keys.lua")
    local reverse = {}

    for symbolic_name, weapon_key in pairs(dev_keys) do
        H.equal(stable_keys[symbolic_name], weapon_key,
            "stable/dev documented-key drift for " .. symbolic_name)
        H.equal(reverse[weapon_key], nil, "duplicate documented key " .. weapon_key)
        reverse[weapon_key] = symbolic_name
    end

    H.test("WT #159 weapon key registry is localized and stream-identical", function()
        H.equal(count(dev_keys), 83)
        H.equal(count(stable_keys), 83)

        local source = read(dev_root .. "wt_documented_keys.lua")
        local declared = 0
        for line in source:gmatch("[^\r\n]+") do
            local symbolic_name, weapon_key, display_name = line:match(
                '^%s*([A-Z][A-Z0-9_]*)%s*=%s*"([^"]+)",%s*%-%-%s*(.-)%s*$')
            if symbolic_name then
                declared = declared + 1
                H.equal(dev_keys[symbolic_name], weapon_key)
                H.truthy(display_name:find(": ", 1, true),
                    weapon_key .. " lacks an adjacent player-facing name")
            end
        end
        H.equal(declared, 83)

        local stable_source = read(stable_root .. "wt_documented_keys.lua")
        H.equal(stable_source, source, "stable/dev documented-key files must be byte-identical")
    end)

    H.test("WT #159 unlock and routing data use documented symbolic keys", function()
        local function strip_comments(source)
            source = source:gsub("%-%-%[%[[%s%S]-%]%]", "")
            return source:gsub("%-%-[^\r\n]*", "")
        end

        for _, root in ipairs({ stable_root, dev_root }) do
            for _, file_name in ipairs({
                "wt_unlock_data.lua",
                "wt_wield_patches.lua",
                root == dev_root and "wt_port_status.lua" or nil,
            }) do
                if file_name then
                    local source = strip_comments(read(root .. file_name))
                    for token in source:gmatch("[%a][%w_]+") do
                        H.equal(reverse[token], nil,
                            root .. file_name .. " repeats raw weapon key " .. token)
                    end
                end
            end
        end

        -- The dev overlay deliberately expands from live ItemMasterList at runtime,
        -- so its post-overlay rows cannot be enumerated in an offline source test.
        -- Stable owns the authored table shared by both streams.
        local data = dofile(stable_root .. "wt_unlock_data.lua")
        for career, weapons in pairs(data.weapon_unlock_map) do
            for _, weapon_key in ipairs(weapons) do
                H.truthy(reverse[weapon_key],
                    career .. " uses undocumented weapon key " .. tostring(weapon_key))
            end
        end

    end)

    H.test("WT #159 localized annotations match current menu vocabulary", function()
        local localization = read(dev_root .. "weapon_tweaker_dev_localization.lua")
        local registry_source = read(dev_root .. "wt_documented_keys.lua")

        for line in registry_source:gmatch("[^\r\n]+") do
            local weapon_key, display_name = line:match(
                '^%s*[A-Z][A-Z0-9_]*%s*=%s*"([^"]+)",%s*%-%-%s*(.-)%s*$')
            if weapon_key then
                H.truthy(localization:find('"' .. display_name .. '"', 1, true),
                    weapon_key .. " annotation is absent from current menu localization")
            end
        end

        local wield_source = read(dev_root .. "wt_wield_patches.lua")
        H.truthy(wield_source:find(
            'cwv_combat_style_empire_spear_shield = "es_deus_01_template", -- Kruber: Spear and Shield',
            1, true))
    end)
end
