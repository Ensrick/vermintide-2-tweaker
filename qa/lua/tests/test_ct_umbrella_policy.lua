return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local base = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local policy = assert(loadfile(base .. "_ct_umbrella_policy.lua"))()

local function read(path)
        if tostring(path):find("chaos_wastes_tweaker_dev.lua", 1, true) then
            return CTSource.expanded(repo_root)
        end
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function realize_data()
        local loc
        local adventure = {
            build_loc_entries = function() return {} end,
            build_campaign_dlc_group_widgets = function() return {} end,
            build_cw_scenarios_block = function()
                return { setting_id = "fixture_cw", type = "group", sub_widgets = {} }
            end,
            build_event_missions_block = function()
                return { setting_id = "fixture_event", type = "group", sub_widgets = {} }
            end,
        }
        local missions = {
            build_menu_group = function()
                return { setting_id = "fixture_missions", type = "group", sub_widgets = {} }
            end,
            build_loc_entries = function() return {} end,
        }
        local mod = {
            dofile = function(_, path)
                if path:find("_adventure_pool", 1, true) then return adventure end
                if path:find("_ct_dev_mission_catalog", 1, true) then return missions end
                error("unexpected dependency " .. tostring(path))
            end,
            localize = function(_, key)
                local entry = loc and loc[key]
                return entry and entry.en or "<" .. tostring(key) .. ">"
            end,
        }
        local old_get_mod = get_mod
        get_mod = function() return mod end
        loc = assert(loadfile(base .. "chaos_wastes_tweaker_dev_localization.lua"))()
        local data = assert(loadfile(base .. "chaos_wastes_tweaker_dev_data.lua"))()
        get_mod = old_get_mod
        return data
    end

    H.test("CT #221 umbrella policy preserves old leaf behavior by default", function()
        H.equal(policy.enabled(true, true), true)
        H.equal(policy.enabled(true, false), false)
        H.equal(policy.enabled(false, true), false)
        H.equal(policy.banned(false, true), true)
        H.equal(policy.banned(false, false), false)
        H.equal(policy.banned(true, false), true)
        H.equal(policy.value(true, 7, 1), 7)
        H.equal(policy.value(false, 7, 1), 1)

        local unchanged, removed = policy.filter_traits(false,
            { "keep", "also_keep" }, function() return false end)
        H.equal(#unchanged, 2)
        H.equal(removed, 0)

        local filtered
        filtered, removed = policy.filter_traits(false,
            { "keep", "ban" }, function(name) return name == "ban" end)
        H.equal(#filtered, 1)
        H.equal(filtered[1], "keep")
        H.equal(removed, 1)

        filtered, removed = policy.filter_traits(true,
            { "one", "two" }, function() return false end)
        H.equal(#filtered, 0)
        H.equal(removed, 2)
    end)

    H.test("CT #221 realizes five accessible masters with bounded families", function()
        local data = realize_data()
        local masters = {}
        local catalog = {}
        local wanted = {
            enable_altar_reuse = { default = true, prefix = "altar_reuse_", count = 8 },
            disable_all_listed_curses = { default = false, prefix = "disable_curse_", count = 14 },
            ban_all_grudge_marks = { default = false, prefix = "ban_grudge_mark_", count = 13 },
            ban_all_traits = { default = false, prefix = "ban_trait_", count = 34 },
            enable_boon_reworks = { default = true, prefix = "enable_boon_", count = 5 },
        }
        local function visit(node)
            if type(node) ~= "table" then return end
            if wanted[node.setting_id] then masters[node.setting_id] = node end
            if type(node.setting_id) == "string" then catalog[node.setting_id] = node end
            for _, field in ipairs({ "widgets", "sub_widgets" }) do
                for _, child in ipairs(node[field] or {}) do visit(child) end
            end
        end
        visit(data.options)
        for id, spec in pairs(wanted) do
            local master = masters[id]
            H.truthy(master, "missing master " .. id)
            H.equal(master.type, "checkbox")
            H.equal(master.default_value, spec.default)
            local count = 0
            for setting_id, node in pairs(catalog) do
                if setting_id ~= id and node.type ~= "group"
                        and setting_id:find("^" .. spec.prefix) then
                    count = count + 1
                end
            end
            H.equal(count, spec.count, id .. " family drift")
            if spec.default == false then
                H.equal(master.sub_widgets, nil,
                    id .. " must not hide individually configurable leaves while off")
            else
                H.truthy(type(master.sub_widgets) == "table" and #master.sub_widgets > 0,
                    id .. " should hide inactive dependent tuning while off")
            end
        end
    end)

    H.test("CT #221 production gates every owner and exposes bounded diagnostics", function()
        -- #1159: `enable_altar_reuse` is consumed by the altar-reuse owner now
        -- that the whole reusable-altar block left the entry. The gate follows
        -- the code: same needles, one more file in the scanned set.
        local source = read(base .. "chaos_wastes_tweaker_dev.lua")
            .. read(base .. "_ct_boon_balance.lua")
            .. read(base .. "_ct_meta_trait_boons.lua")
            .. read(base .. "_ct_weapon_trait_generation.lua")
            .. read(base .. "_ct_altar_reuse_owner.lua")
        for _, id in ipairs({
            "enable_altar_reuse", "disable_all_listed_curses",
            "ban_all_grudge_marks", "ban_all_traits", "enable_boon_reworks",
        }) do
            H.truthy(source:find('effective_setting("' .. id .. '")', 1, true), id .. " not consumed")
        end
        H.truthy(source:find("mod._ct_umbrella_policy.value", 1, true))
        H.truthy(source:find("mod._ct_umbrella_policy.banned", 1, true))
        H.truthy(source:find("mod._ct_umbrella_policy.enabled", 1, true))
        H.truthy(source:find("mod._ct_strip_banned_traits_from_result", 1, true))
        H.truthy(source:find("result = override_traits_in_result", 1, true))
        H.truthy(source:find("return mod._ct_strip_banned_traits_from_result(result)", 1, true))
        H.truthy(source:find('mod:command("ct_umbrella_audit"', 1, true))
        H.truthy(source:find("mutation=false", 1, true))
        for _, field in ipairs({
            "altar_master=", "curses_master=", "grudges_master=",
            "traits_master=", "boons_master=",
        }) do
            H.truthy(source:find(field, 1, true), "missing audit field " .. field)
        end
    end)
end
