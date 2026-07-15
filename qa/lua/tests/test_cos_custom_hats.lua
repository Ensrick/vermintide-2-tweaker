return function(H, repo_root)
    local function isolated(callback)
        local saved_get_mod = _G.get_mod
        local saved_iml = _G.ItemMasterList
        local saved_lookup = _G.NetworkLookup
        local saved_clone = table.clone
        local setting = true
        local backend_entries = nil
        local mod = {
            get = function(_, id)
                if id == "cos_encarmine_hat_enabled" then return setting end
            end,
            add_mod_items_to_masterlist = function(_, entries)
                for _, entry in ipairs(entries) do
                    ItemMasterList[entry.name] = entry
                    local index = #NetworkLookup.item_names + 1
                    NetworkLookup.item_names[index] = entry.name
                    NetworkLookup.item_names[entry.name] = index
                end
            end,
            add_mod_items_to_local_backend = function(_, entries)
                backend_entries = entries
            end,
            info = function() end,
        }
        _G.get_mod = function(name)
            if name == "cosmetics_tweaker" then return mod end
        end
        _G.ItemMasterList = {
            knight_hat_0006 = {
                key = "knight_hat_0006",
                name = "knight_hat_0006",
                template = "es_hats_no_ear_moustache",
                slot_type = "hat",
                item_type = "hat",
                unit = "units/beings/player/empire_soldier_knight/headpiece/es_k_hat_07",
                rarity = "exotic",
                can_wield = { "es_knight" },
            },
        }
        _G.NetworkLookup = { item_names = {} }
        table.clone = function(source)
            local out = {}
            for k, v in pairs(source) do out[k] = v end
            return out
        end

        local path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_custom_hats.lua"
        local hats = assert(loadfile(path))()
        local bridge = {
            registered = false,
            la_registered = false,
            backend_to_armoury = {},
            backend_to_vanilla = {},
            armoury_to_backend = {},
            unit_path_to_clones = {},
        }
        local ok, err = pcall(callback, hats, bridge, function(value) setting = value end,
            function() return backend_entries end)
        _G.get_mod = saved_get_mod
        _G.ItemMasterList = saved_iml
        _G.NetworkLookup = saved_lookup
        table.clone = saved_clone
        if not ok then error(err, 0) end
    end

    H.test("Encarmine hat registers a stable non-DLC item and fallback", function()
        isolated(function(hats, bridge, _, get_backend_entries)
            H.truthy(hats.register_all(bridge))
            local entry = ItemMasterList.cos_encarmine_hat
            H.truthy(entry)
            H.equal(entry.template, "es_hats_no_ear_moustache")
            H.equal(entry.inventory_icon, "icon_knight_hat_0006_encarmine")
            H.equal(entry.unit, hats.CUSTOM_UNIT)
            H.equal(entry.required_dlc, nil)
            H.equal(entry.can_wield[1], "es_knight")
            H.equal(bridge.backend_to_vanilla.cos_encarmine_hat, "knight_hat_0006")
            H.equal(bridge.backend_to_armoury.cos_encarmine_hat, hats.VARIANT_KEY)
            H.truthy(bridge.registered)
            H.equal(bridge.la_registered, false)
            H.equal(get_backend_entries()[1].mod_data.backend_id, "cos_encarmine_hat")
        end)
    end)

    H.test("Encarmine toggle fails closed without changing lookup identity", function()
        isolated(function(hats, bridge, set_setting)
            H.truthy(hats.register_all(bridge))
            set_setting(false)
            H.truthy(hats.sync_toggle())
            local entry = ItemMasterList.cos_encarmine_hat
            H.equal(entry.unit, hats.BASE_UNIT)
            H.equal(#entry.can_wield, 0)
            local fallback = hats.resolve_variant(hats.VARIANT_KEY)
            H.equal(fallback.new_units[1], hats.BASE_UNIT)
            H.equal(fallback.enabled, false)
            H.truthy(NetworkLookup.item_names.cos_encarmine_hat)
        end)
    end)

    H.test("Encarmine package assets and icon declarations exist", function()
        local files = {
            "/cosmetics_tweaker/units/cosmetics_tweaker/encarmine_hat/encarmine_hat.fbx",
            "/cosmetics_tweaker/units/cosmetics_tweaker/encarmine_hat/encarmine_hat.unit",
            "/cosmetics_tweaker/textures/cosmetics_tweaker/encarmine_hat/encarmine_armored_diffuse.png",
            "/cosmetics_tweaker/textures/cosmetics_tweaker/encarmine_hat/encarmine_cloth_diffuse.png",
            "/cosmetics_tweaker/gui/1080p/single_textures/cosmetics_tweaker/icon_knight_hat_0006_encarmine.png",
        }
        for _, suffix in ipairs(files) do
            local f = io.open(repo_root .. suffix, "rb")
            H.truthy(f, "missing " .. suffix)
            if f then f:close() end
        end
    end)
end
