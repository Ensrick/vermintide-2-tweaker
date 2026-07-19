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

    H.test("CRT data nests both live masters in their own group", function()
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
            if widget.setting_id == module.MASTER_ENSRICK or widget.setting_id == module.MASTER_TOURNEY then
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
