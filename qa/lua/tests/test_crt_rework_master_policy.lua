return function(H, repo_root)
    local policy_path = repo_root
        .. "/career_tweaker/scripts/mods/career_tweaker/_crt_rework_master_policy.lua"
    local module = assert(loadfile(policy_path))()
    local policy = module.new({ rework_b = {}, rework_a = {} }, { "trn_b", "trn_a" })

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

    H.test("CRT active rework labels carry derived family suffixes", function()
        local loc_path = repo_root
            .. "/career_tweaker/scripts/mods/career_tweaker/career_tweaker_localization.lua"
        local localization = assert(loadfile(loc_path))()
        local checked = 0
        for key, row in pairs(localization) do
            local family = key:find("^rework_") and "Ensrick's Reworks"
                or (key:find("^trn_") and "Tourney Balance")
            local leaf = family
                and not key:find("_group$")
                and not key:find("_description$")
                and not key:find("_tooltip$")
                and not key:find("^rework_master_")
            if leaf then
                H.truthy(row.en:find("[" .. family .. "]", 1, true), key .. " missing family suffix")
                checked = checked + 1
            end
        end
        H.truthy(checked > 50, "expected the complete active rework catalog")
        H.equal(localization.rework_master_group.en:find("[Ensrick", 1, true), nil,
            "navigation/master rows should remain undecorated")
    end)

    H.test("CRT data exposes both live masters as plain checkboxes", function()
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
        local function visit(widget)
            if type(widget) ~= "table" then return end
            if widget.setting_id == module.MASTER_ENSRICK or widget.setting_id == module.MASTER_TOURNEY then
                found[widget.setting_id] = widget.type
            end
            for _, child in ipairs(widget.sub_widgets or {}) do visit(child) end
        end
        for _, widget in ipairs(data.options and data.options.widgets or {}) do visit(widget) end
        H.equal(found[module.MASTER_ENSRICK], "checkbox")
        H.equal(found[module.MASTER_TOURNEY], "checkbox")
    end)
end
