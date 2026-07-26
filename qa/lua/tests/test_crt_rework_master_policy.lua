return function(H, repo_root)
    local policy_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_rework_master_policy.lua"
    local module = assert(loadfile(policy_path))()
    local policy = module.new({ rework_b = {}, rework_a = {} }, { "trn_b", "trn_a" })

    local function load_localization()
        local require_key = "scripts/mods/career_tweaker/_crt_rework_master_policy"
        local previous = package.preload[require_key]
        package.preload[require_key] = function() return module end
        local loc_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_localization.lua"
        local ok, localization = pcall(assert(loadfile(loc_path)))
        package.preload[require_key] = previous
        H.truthy(ok, tostring(localization))
        return localization
    end

    local function change_map(changes)
        local out = {}
        for i = 1, #changes do
            H.equal(out[changes[i].id], nil, "duplicate write for " .. changes[i].id)
            out[changes[i].id] = changes[i].value
        end
        return out
    end

    H.test("CRT rework master enables one complete family in one bounded plan", function()
        local changes = policy:plan("ensrick", true, {
            rework_a = false, rework_b = false, trn_a = true, trn_b = false,
            [module.MASTER_ENSRICK] = false, [module.MASTER_TOURNEY] = true,
        })
        local got = change_map(changes)
        H.equal(#changes, 5, "only changed leaves and master flags should be written")
        H.equal(got.rework_a, true)
        H.equal(got.rework_b, true)
        H.equal(got.trn_a, false)
        H.equal(got[module.MASTER_ENSRICK], true)
        H.equal(got[module.MASTER_TOURNEY], false)
        H.equal(got.trn_b, nil, "already-false rival leaf should not be rewritten")
    end)

    H.test("CRT rework master off clears only its own family", function()
        local changes = change_map(policy:plan("tourney", false, {
            rework_a = true, rework_b = false, trn_a = true, trn_b = true,
            [module.MASTER_TOURNEY] = true,
        }))
        H.equal(changes.trn_a, false)
        H.equal(changes.trn_b, false)
        H.equal(changes[module.MASTER_TOURNEY], false)
        H.equal(changes.rework_a, nil, "custom rival state must be preserved")
    end)

    H.test("CRT rework master indicators represent exact family state", function()
        local partial = policy:derive_masters({ rework_a=true, rework_b=false, trn_a=false, trn_b=false })
        H.equal(partial[module.MASTER_ENSRICK], false)
        H.equal(partial[module.MASTER_TOURNEY], false)
        local exact = policy:derive_masters({ rework_a=false, rework_b=false, trn_a=true, trn_b=true })
        H.equal(exact[module.MASTER_ENSRICK], false)
        H.equal(exact[module.MASTER_TOURNEY], true)
    end)

    H.test("CRT all-reworks master plans both families without per-leaf callback fanout", function()
        local got = change_map(policy:plan("all", true, {
            rework_a = false, rework_b = true, trn_a = false, trn_b = true,
        }))
        H.equal(got.rework_a, true)
        H.equal(got.rework_b, nil)
        H.equal(got.trn_a, true)
        H.equal(got.trn_b, nil)
        H.equal(got[module.MASTER_ENSRICK], nil)
        H.equal(got[module.MASTER_TOURNEY], nil)
        H.equal(got[module.MASTER_ALL], true)

        local exact = policy:derive_masters({ rework_a=true, rework_b=true, trn_a=true, trn_b=true })
        H.equal(exact[module.MASTER_ENSRICK], false)
        H.equal(exact[module.MASTER_TOURNEY], false)
        H.equal(exact[module.MASTER_ALL], true)
    end)

    H.test("CRT family and all masters reconcile Foot Knight secondary carriers once", function()
        local globals = {
            get_mod = _G.get_mod,
            BuffTemplates = _G.BuffTemplates,
            BuffFunctionTemplates = _G.BuffFunctionTemplates,
            CareerSettings = _G.CareerSettings,
            SPProfiles = _G.SPProfiles,
            HeroWindowLoadoutInventory = _G.HeroWindowLoadoutInventory,
            HeroWindowLoadoutInventoryConsole = _G.HeroWindowLoadoutInventoryConsole,
            printf = _G.printf,
        }
        local perk_key = "scripts/unit_extensions/default_player_unit/buffs/settings/buff_perk_names"
        local old_preload = package.preload[perk_key]
        local old_loaded = package.loaded[perk_key]
        local settings = {}
        local backend_types = { "ranged" }
        local menu_types = { "ranged" }
        local mock = {
            get = function(_, id) return settings[id] end,
            dofile = function(_, path)
                return assert(loadfile(repo_root .. "/career_tweaker/" .. path .. ".lua"))()
            end,
            hook = function() end,
        }

        _G.get_mod = function() return mock end
        _G.BuffTemplates = {}
        _G.BuffFunctionTemplates = nil
        _G.CareerSettings = {
            es_knight = {
                name = "es_knight",
                item_slot_types_by_slot_name = { slot_ranged = backend_types },
            },
        }
        _G.SPProfiles = {
            [4] = {
                careers = {
                    [3] = {
                        name = "es_knight",
                        item_slot_types_by_slot_name = { slot_ranged = menu_types },
                    },
                },
            },
        }
        _G.HeroWindowLoadoutInventory = nil
        _G.HeroWindowLoadoutInventoryConsole = nil
        _G.printf = function() end
        package.loaded[perk_key] = nil
        package.preload[perk_key] = function()
            return { uninterruptible_heavy = "uninterruptible_heavy" }
        end

        local foot_knight
        local ok, err = pcall(function()
            foot_knight = assert(loadfile(
                repo_root .. "/career_tweaker/scripts/mods/career_tweaker/_crt_foot_knight.lua"))()
            local master_policy = module.new({
                rework_es_knight_secondary_melee = {},
                rework_other = {},
            }, {
                trn_other = {},
            })

            local function exercise(family)
                settings = {}
                foot_knight.apply_settings()
                H.deep_equal(backend_types, { "ranged" })
                H.deep_equal(menu_types, { "ranged" })

                local batch = false
                local writer_calls, callback_calls = 0, 0
                local nested_owner_applies, engine_applies, live_applies = 0, 0, 0
                local function nested_setting_callback()
                    callback_calls = callback_calls + 1
                    if batch then return end
                    nested_owner_applies = nested_owner_applies + 1
                end
                local function write_changes(changes)
                    writer_calls = writer_calls + 1
                    batch = true
                    for _, change in ipairs(changes) do
                        settings[change.id] = change.value
                        nested_setting_callback()
                    end
                    batch = false
                    return true
                end

                local applied, changes = module.apply_bounded_master(
                    master_policy, family, true, settings,
                    write_changes,
                    function() engine_applies = engine_applies + 1 end,
                    function()
                        live_applies = live_applies + 1
                        foot_knight.apply_settings()
                    end)
                H.equal(applied, true)
                H.equal(writer_calls, 1)
                H.equal(callback_calls, #changes)
                H.equal(nested_owner_applies, 0,
                    "programmatic leaf callbacks must stay under the batch guard")
                H.equal(engine_applies, 1)
                H.equal(live_applies, 1)
                H.deep_equal(backend_types, { "melee", "ranged" })
                H.deep_equal(menu_types, { "melee", "ranged" })

                settings.rework_es_knight_secondary_melee = false
                foot_knight.apply_settings()
            end

            exercise("ensrick")
            exercise("all")
        end)

        if foot_knight then pcall(foot_knight.restore) end
        package.preload[perk_key] = old_preload
        package.loaded[perk_key] = old_loaded
        _G.get_mod = globals.get_mod
        _G.BuffTemplates = globals.BuffTemplates
        _G.BuffFunctionTemplates = globals.BuffFunctionTemplates
        _G.CareerSettings = globals.CareerSettings
        _G.SPProfiles = globals.SPProfiles
        _G.HeroWindowLoadoutInventory = globals.HeroWindowLoadoutInventory
        _G.HeroWindowLoadoutInventoryConsole = globals.HeroWindowLoadoutInventoryConsole
        _G.printf = globals.printf
        H.truthy(ok, tostring(err))
    end)

    H.test("CRT rework engines preserve the selected owner across conflict transitions", function()
        local value = 5
        local tourney_saved
        local balance_saved
        local tourney_on = true
        local ensrick_on = false

        local tourney = {
            restore = function()
                if tourney_saved ~= nil then value = tourney_saved end
                tourney_saved = nil
            end,
            apply = function()
                if tourney_saved ~= nil then value = tourney_saved end
                tourney_saved = nil
                if tourney_on and not ensrick_on then
                    tourney_saved = value
                    value = 20
                end
            end,
        }
        local balance = {
            apply = function()
                if balance_saved ~= nil then value = balance_saved end
                balance_saved = nil
                if ensrick_on then
                    balance_saved = value
                    value = 999
                end
            end,
        }

        module.reconcile_engines(balance, tourney)
        H.equal(value, 20, "Tourney should own the field before the conflict is selected")

        ensrick_on = true
        module.reconcile_engines(balance, tourney)
        H.equal(value, 999, "Tourney restore must not clobber the newly selected Ensrick value")

        ensrick_on = false
        module.reconcile_engines(balance, tourney)
        H.equal(value, 20, "Tourney should resume after the Ensrick conflict is cleared")
    end)

    H.test("CRT active rework labels carry derived family prefixes", function()
        local localization = load_localization()
        local checked = 0
        for key, row in pairs(localization) do
            if module.is_leaf_localization_key(key) then
                local _, metadata = module.family_for_setting(key)
                H.equal(row.en:sub(1, #metadata.label_prefix), metadata.label_prefix,
                    key .. " missing family prefix")
                H.equal(row.en:find("[Ensrick's Reworks]", 1, true), nil,
                    key .. " retained superseded suffix")
                checked = checked + 1
            end
        end
        H.truthy(checked > 50, "expected the complete active rework catalog")
        H.equal(localization.rework_master_group.en, "Master Toggles")
        H.equal(localization.rework_master_ensrick.en:find("[Ensrick", 1, true), nil,
            "navigation/master rows should remain undecorated")
    end)

    H.test("CRT data nests all three live presets in their own group", function()
        local old_get_mod = _G.get_mod
        _G.get_mod = function()
            return { localize = function(_, id) return id end }
        end
        local data_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_data.lua"
        local ok, data = pcall(assert(loadfile(data_path)))
        _G.get_mod = old_get_mod
        H.truthy(ok, tostring(data))

        local found = {}
        local master_group_parent
        local function visit(widget, parent_id)
            if type(widget) ~= "table" then return end
            if widget.setting_id == "rework_master_group" then
                master_group_parent = parent_id
                H.equal(widget.type, "group")
            end
            if widget.setting_id == module.MASTER_ENSRICK or widget.setting_id == module.MASTER_TOURNEY
                    or widget.setting_id == module.MASTER_ALL then
                found[widget.setting_id] = { type = widget.type, parent = parent_id }
            end
            for _, child in ipairs(widget.sub_widgets or {}) do visit(child, widget.setting_id) end
        end
        for _, widget in ipairs(data.options and data.options.widgets or {}) do visit(widget, nil) end
        H.equal(master_group_parent, "talent_reworks_group")
        H.equal(found[module.MASTER_ENSRICK].type, "checkbox")
        H.equal(found[module.MASTER_ENSRICK].parent, "rework_master_group")
        H.equal(found[module.MASTER_TOURNEY].type, "checkbox")
        H.equal(found[module.MASTER_TOURNEY].parent, "rework_master_group")
        H.equal(found[module.MASTER_ALL].type, "checkbox")
        H.equal(found[module.MASTER_ALL].parent, "rework_master_group")
    end)

    H.test("CRT every visible rework checkbox has one family prefix", function()
        local old_get_mod = _G.get_mod
        _G.get_mod = function()
            return { localize = function(_, id) return id end }
        end
        local data_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_data.lua"
        local ok, data = pcall(assert(loadfile(data_path)))
        _G.get_mod = old_get_mod
        H.truthy(ok, tostring(data))
        local localization = load_localization()

        local checked = 0
        local function visit(widget)
            if type(widget) ~= "table" then return end
            local family, metadata = module.family_for_setting(widget.setting_id)
            if family and widget.type == "checkbox" then
                local row = localization[widget.setting_id]
                H.truthy(type(row) == "table" and type(row.en) == "string",
                    widget.setting_id .. " missing localization")
                H.equal(row.en:sub(1, #metadata.label_prefix), metadata.label_prefix,
                    widget.setting_id .. " missing exact authorship prefix")
                checked = checked + 1
            end
            for _, child in ipairs(widget.sub_widgets or {}) do visit(child) end
        end
        for _, widget in ipairs(data.options and data.options.widgets or {}) do visit(widget) end
        H.truthy(checked > 50, "expected every active visible rework checkbox")
    end)
end
