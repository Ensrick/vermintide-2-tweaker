return function(H, repo_root)
    local dev_root = repo_root .. "/weapon_tweaker_dev/"
    local script_root = dev_root .. "scripts/mods/weapon_tweaker_dev/"
    local policy = dofile(script_root .. "wt_universal_availability.lua")

    local function with_dev_mod(cwv_active, fn)
        local previous_get_mod = get_mod
        local previous_printf = printf
        local mod = {}
        function mod:dofile(path)
            return dofile(dev_root .. path .. ".lua")
        end
        function mod:localize(key) return key end
        function mod:get() return false end
        function mod:debug() end
        function mod:info() end
        function mod:warning() end
        function mod:echo() end
        function mod:command() end
        function mod:set() end
        local cwv = cwv_active and {
            is_enabled = function() return true end,
        } or nil
        get_mod = function(name)
            if name == "wt_dev" then return mod end
            if name == "character_weapon_variants" then return cwv end
        end
        printf = function() end
        local ok, result = pcall(fn, mod)
        get_mod = previous_get_mod
        printf = previous_printf
        if not ok then error(result, 0) end
        return result
    end

    local function index_widgets(nodes, index)
        for _, node in ipairs(nodes or {}) do
            if type(node) == "table" then
                if type(node.setting_id) == "string" then
                    H.equal(index[node.setting_id], nil,
                        "duplicate setting id " .. node.setting_id)
                    index[node.setting_id] = node
                end
                index_widgets(node.sub_widgets, index)
            end
        end
    end

    H.test("WT dev #948 roster is 83 weapons across 20 careers", function()
        H.equal(#policy.melee_weapons, 52)
        H.equal(#policy.ranged_weapons, 31)
        H.equal(#policy.all_weapons, 83)
        H.equal(#policy.careers, 20)

        local data = with_dev_mod(false, function()
            return dofile(script_root .. "wt_unlock_data.lua")
        end)
        for _, career in ipairs(policy.careers) do
            local list = data.weapon_unlock_map[career.key]
            H.equal(#list, 83, career.key .. " roster size")
            local seen = {}
            for _, key in ipairs(list) do
                H.equal(seen[key], nil, career.key .. " duplicate " .. key)
                seen[key] = true
            end
            for _, key in ipairs(policy.all_weapons) do
                H.truthy(seen[key], career.key .. " missing " .. key)
            end
        end
    end)

    H.test("WT dev #948 preserves verified #368 conditional representatives", function()
        local data = with_dev_mod(false, function()
            return dofile(script_root .. "wt_unlock_data.lua")
        end)
        local managed = data.cwv_conditional_managed
        local expected = {
            "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
            "wh_captain", "wh_bountyhunter", "wh_zealot",
        }
        local count = 0
        for career, rows in pairs(managed) do
            count = count + 1
            H.truthy(rows.dr_shield_axe, career .. " lost Axe and Shield handoff")
            H.truthy(rows.dr_2h_axe, career .. " lost Greataxe handoff")
        end
        H.equal(count, #expected)
        for _, career in ipairs(expected) do H.truthy(managed[career]) end
    end)

    H.test("WT dev #948 generates every base availability widget", function()
        local map = {}
        policy.expand_unlock_map(map)
        local availability = { setting_id = "weapon_availability", sub_widgets = {} }
        for _, character in ipairs({ "kruber", "bardin", "kerillian", "saltzpyre", "sienna" }) do
            availability.sub_widgets[#availability.sub_widgets + 1] = {
                setting_id = character .. "_melee_group", sub_widgets = {},
            }
            availability.sub_widgets[#availability.sub_widgets + 1] = {
                setting_id = character .. "_ranged_group", sub_widgets = {},
            }
        end
        local data = { options = { widgets = { availability } } }
        H.equal(policy.ensure_base_widgets(data, map), 1660)
        H.equal(policy.ensure_base_widgets(data, map), 0)

        local found_wp_ranged = false
        local function walk(nodes)
            for _, node in ipairs(nodes or {}) do
                if node.setting_id == "ranged_wh_priest" then
                    found_wp_ranged = true
                    H.equal(#node.sub_widgets, 31)
                end
                walk(node.sub_widgets)
            end
        end
        walk(data.options.widgets)
        H.truthy(found_wp_ranged)
    end)

    H.test("WT dev #948 generates localized labels for every receiver", function()
        local loc = {}
        for _, weapon_key in ipairs(policy.all_weapons) do
            loc["unlock_es_mercenary_" .. weapon_key] = {
                en = "Test Owner: " .. weapon_key,
            }
        end
        local labels = policy.ensure_base_localization(loc)
        for _, weapon_key in ipairs(policy.all_weapons) do
            H.truthy(labels[weapon_key])
        end
        for _, career in ipairs(policy.careers) do
            for _, weapon_key in ipairs(policy.all_weapons) do
                local entry = loc["unlock_" .. career.key .. "_" .. weapon_key]
                H.truthy(entry)
                H.truthy(entry.en ~= weapon_key, "raw key leaked for " .. weapon_key)
            end
        end
        H.equal(loc.ranged_wh_priest.en, "Ranged: Warrior Priest")
    end)

    H.test("WT dev #948 exposes each CWV variant to all careers default-off", function()
        local catalog = with_dev_mod(false, function()
            return dofile(script_root .. "wt_cwv_variant_catalog.lua")
        end)
        policy.expand_cwv_catalog(catalog)
        H.equal(#catalog, 32)
        for _, variant in ipairs(catalog) do
            H.equal(#variant.careers, 20, variant.key .. " career count")
            local authored = {}
            for _, career in ipairs(variant.authored_careers or {}) do authored[career] = true end
            local conditional = {}
            for _, career in ipairs(variant.conditional_careers or {}) do conditional[career] = true end
            for _, career in ipairs(policy.careers) do
                if authored[career.key] then
                    H.equal(conditional[career.key], nil,
                        variant.key .. " authored receiver became WT-owned")
                else
                    H.truthy(conditional[career.key],
                        variant.key .. " missing conditional receiver " .. career.key)
                end
            end
        end
        local rapier
        for _, variant in ipairs(catalog) do
            if variant.key == "cwv_es_rapier" then rapier = variant; break end
        end
        H.truthy(rapier)
        local defaults = {}
        for _, career in ipairs(rapier.default_careers) do defaults[career] = true end
        H.truthy(defaults.es_mercenary)
        H.equal(defaults.wh_priest, nil)
        H.equal(defaults.bw_necromancer, nil)
    end)

    H.test("WT dev #948 production menu evaluates with unique bounded rows", function()
        local result = with_dev_mod(true, function(mod)
            local loc = dofile(script_root .. "weapon_tweaker_dev_localization.lua")
            local data = dofile(script_root .. "weapon_tweaker_dev_data.lua")
            return { mod = mod, loc = loc, data = data }
        end)
        local index = {}
        index_widgets(result.data.options.widgets, index)

        local cwv_policy = with_dev_mod(false, function()
            return dofile(script_root .. "_wt_cwv_availability_policy.lua")
        end)
        local cwv_catalog = with_dev_mod(false, function()
            return dofile(script_root .. "wt_cwv_variant_catalog.lua")
        end)
        policy.expand_cwv_catalog(cwv_catalog)
        local expected_cwv_children = {}
        for _, variant in ipairs(cwv_catalog) do
            for _, career in ipairs(variant.careers) do
                expected_cwv_children[cwv_policy.career_setting_id(
                    variant.key, career)] = true
            end
        end
        local base_count = 0
        local cwv_count = 0
        for setting_id in pairs(index) do
            if expected_cwv_children[setting_id] then
                cwv_count = cwv_count + 1
            elseif setting_id:match("^unlock_")
                    and not setting_id:match("^unlock_cwv_variant_") then
                base_count = base_count + 1
            end
        end
        -- 1,660 base cells minus the fourteen #368 representatives hidden
        -- while CWV is active; all 32 x 20 CWV cells remain available.
        H.equal(base_count, 1646)
        H.equal(cwv_count, 640)
        H.truthy(index.ranged_wh_priest)
        H.equal(index.unlock_es_mercenary_dr_shield_axe, nil)
        H.truthy(index.unlock_cwv_variant_es_mercenary_cwv_es_axe_shield)
        for _, career in ipairs(policy.careers) do
            for _, weapon_key in ipairs(policy.all_weapons) do
                local setting_id = "unlock_" .. career.key .. "_" .. weapon_key
                if index[setting_id] then
                    local entry = result.loc[setting_id]
                    H.truthy(type(entry) == "table" and type(entry.en) == "string",
                        "missing localization " .. setting_id)
                    H.truthy(entry.en ~= weapon_key,
                        "raw key localization " .. setting_id)
                end
            end
        end
    end)
end
