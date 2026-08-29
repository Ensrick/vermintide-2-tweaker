return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count = 0
        local offset = 1
        while true do
            local found = source:find(needle, offset, true)
            if not found then return count end
            count = count + 1
            offset = found + #needle
        end
    end

    H.test("CRT balance hook extraction preserves one load and four owners", function()
        local root = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/"
        local balance = read(root .. "career_tweaker_balance.lua")
        local hooks = read(root .. "_career_tweaker_balance_hooks.lua")

        H.truthy(balance:find(
            'mod:dofile("scripts/mods/career_tweaker/_career_tweaker_balance_hooks")',
            1, true))
        H.equal(balance:find('mod:hook("TalentExtension", "has_talent_perk"', 1, true), nil)
        H.equal(balance:find('mod:hook(_G, "Localize"', 1, true), nil)
        H.equal(balance:find('mod:hook("BuffSystem", "hot_join_sync"', 1, true), nil)

        H.truthy(hooks:find('mod:hook("TalentExtension", "has_talent_perk"', 1, true))
        H.truthy(hooks:find('mod:hook(ActionUtils, "get_critical_strike_chance"', 1, true))
        H.truthy(hooks:find('mod:hook(_G, "Localize"', 1, true))
        H.truthy(hooks:find('mod:hook("BuffSystem", "hot_join_sync"', 1, true))
        H.truthy(hooks:find("mod._crt_hellborgs_crit_hook_installed = true", 1, true))
    end)

    H.test("CRT balance catalogue extraction preserves one dependency-injected owner", function()
        local root = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/"
        local balance = read(root .. "career_tweaker_balance.lua")
        local catalog = read(root .. "_crt_balance_catalog.lua")
        local early = read(root .. "_crt_balance_catalog_early.lua")
        local engineer = read(root .. "_crt_balance_catalog_engineer.lua")
        local focused = read(root .. "_crt_balance_catalog_focused_spirit.lua")
        local late = read(root .. "_crt_balance_catalog_late.lua")
        local owners = { early, engineer, focused, late }
        for _, setting_id in ipairs({
            "rework_dr_engineer_ingenious_ordnance_240s",
            "rework_dr_engineer_leading_shots",
            "rework_dr_engineer_full_head_of_steam_4pct",
        }) do
            local declaration = setting_id .. " = {"
            local total = 0
            for _, owner in ipairs(owners) do
                total = total + count_plain(owner, declaration)
            end
            H.equal(total, 1, setting_id .. " must have one production owner")
            H.equal(count_plain(engineer, declaration), 1,
                setting_id .. " must belong to the Engineer owner")
        end

        H.truthy(balance:find(
            'mod:dofile("scripts/mods/career_tweaker/_crt_balance_catalog")',
            1, true))
        H.equal(balance:find("local BALANCE_MODS = {", 1, true), nil)
        H.truthy(early:find("local BALANCE_MODS = {", 1, true))
        H.truthy(engineer:find("rework_dr_engineer_ingenious_ordnance_240s", 1, true))
        H.truthy(engineer:find("rework_dr_engineer_leading_shots", 1, true))
        H.truthy(engineer:find("rework_dr_engineer_full_head_of_steam_4pct", 1, true))
        H.equal(early:find("rework_dr_engineer_ingenious_ordnance_240s", 1, true), nil)
        H.equal(early:find("rework_dr_engineer_leading_shots", 1, true), nil)
        H.equal(early:find("rework_dr_engineer_full_head_of_steam_4pct", 1, true), nil)
        H.truthy(focused:find("rework_we_maidenguard_focused_spirit_stacks", 1, true))
        H.truthy(late:find("local BALANCE_MODS = {", 1, true))
        H.truthy(catalog:find("local function build(ctx)", 1, true))
        H.truthy(catalog:find(
            'mod:dofile("scripts/mods/career_tweaker/_crt_balance_catalog_early")',
            1, true))
        H.truthy(catalog:find(
            'mod:dofile("scripts/mods/career_tweaker/_crt_balance_catalog_engineer")',
            1, true))
        H.truthy(catalog:find(
            'mod:dofile("scripts/mods/career_tweaker/_crt_balance_catalog_focused_spirit")',
            1, true))
        H.truthy(catalog:find(
            'mod:dofile("scripts/mods/career_tweaker/_crt_balance_catalog_late")',
            1, true))
        H.truthy(balance:find("min_thp_on_kill = _MIN_THP_ON_KILL", 1, true),
            "the extracted catalogue must receive the local THP floor")
        H.truthy(early:find(
            'local _MIN_THP_ON_KILL = assert(ctx.min_thp_on_kill', 1, true),
            "the extracted catalogue must bind the injected THP floor")
        H.truthy(catalog:find("duplicate CRT balance definition", 1, true),
            "catalog composition must reject overlapping setting owners")
        H.truthy(early:find("return BALANCE_MODS", 1, true))
        H.truthy(engineer:find("return BALANCE_MODS", 1, true))
        H.truthy(focused:find("return build", 1, true))
        H.truthy(late:find("return BALANCE_MODS", 1, true))
        H.equal(catalog:find("mod:hook(", 1, true), nil,
            "the catalogue composer must remain hook-neutral")
        H.equal(early:find("mod:hook(", 1, true), nil,
            "the early declarative catalogue must remain hook-neutral")
        H.equal(engineer:find("mod:hook(", 1, true), nil,
            "the Engineer declarative catalogue must remain hook-neutral")
        H.equal(focused:find("mod:hook(", 1, true), nil,
            "the Focused Spirit catalogue must remain hook-neutral")
        H.equal(late:find("mod:hook(", 1, true), nil,
            "the late declarative catalogue must remain hook-neutral")
    end)

    H.test("CRT balance catalogue composer merges disjoint owners and rejects collisions", function()
        local path = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/_crt_balance_catalog.lua"
        local build = assert(loadfile(path))()
        local function context(late_definitions, focused_definitions)
            local fake_mod = {}
            function fake_mod:dofile(module_path)
                if module_path:find("_early", 1, true) then
                    return function() return { early_setting = { character = "markus" } } end
                end
                if module_path:find("_engineer", 1, true) then
                    return function() return { engineer_setting = { character = "bardin" } } end
                end
                if module_path:find("_focused_spirit", 1, true) then
                    return function() return focused_definitions or {} end
                end
                return function() return late_definitions end
            end
            return {
                mod = fake_mod,
                wire_policy = {},
                make_stub = function() return {} end,
                ensure_wire_safe_funcs = function() end,
                min_thp_on_kill = 1.5,
            }
        end

        local composed = build(context({ late_setting = { character = "sienna" } }))
        H.truthy(composed.early_setting)
        H.truthy(composed.engineer_setting)
        H.truthy(composed.late_setting)

        composed = build(context(
            { late_setting = { character = "sienna" } },
            { focused_setting = { character = "kerillian" } }))
        H.truthy(composed.focused_setting)

        local ok, err = pcall(build, context({ early_setting = { character = "bardin" } }))
        H.equal(ok, false)
        H.truthy(tostring(err):find("duplicate CRT balance definition", 1, true))
    end)

    H.test("CRT balance catalogue loads and builds each owner exactly once in declared order", function()
        local path = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/_crt_balance_catalog.lua"
        local build = assert(loadfile(path))()
        local loaded = {}
        local built = {}
        local sentinels = {}
        local fake_mod = {}

        function fake_mod:dofile(module_path)
            local name = module_path:match("([^/]+)$")
            loaded[#loaded + 1] = name
            sentinels[name] = { owner = name }
            return function()
                built[#built + 1] = name
                return { [name] = sentinels[name] }
            end
        end

        local result = build({
            mod = fake_mod,
            wire_policy = {},
            make_stub = function() return {} end,
            ensure_wire_safe_funcs = function() end,
            min_thp_on_kill = 1.5,
        })
        local expected = {
            "_crt_balance_catalog_early",
            "_crt_balance_catalog_engineer",
            "_crt_balance_catalog_focused_spirit",
            "_crt_balance_catalog_late",
        }
        H.deep_equal(loaded, expected)
        H.deep_equal(built, expected)
        for _, name in ipairs(expected) do
            H.equal(result[name], sentinels[name], name .. " definition identity changed")
        end
    end)

    H.test("CRT balance catalogue propagates the exact child error and stops later builders", function()
        local path = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/_crt_balance_catalog.lua"
        local build = assert(loadfile(path))()
        local marker = {}
        local built = { early = 0, engineer = 0, focused = 0, late = 0 }
        local fake_mod = {}

        function fake_mod:dofile(module_path)
            if module_path:find("_early", 1, true) then
                return function()
                    built.early = built.early + 1
                    return { early = {} }
                end
            end
            if module_path:find("_engineer", 1, true) then
                return function()
                    built.engineer = built.engineer + 1
                    error(marker)
                end
            end
            if module_path:find("_focused_spirit", 1, true) then
                return function()
                    built.focused = built.focused + 1
                    return { focused = {} }
                end
            end
            return function()
                built.late = built.late + 1
                return { late = {} }
            end
        end

        local ok, err = pcall(build, {
            mod = fake_mod,
            wire_policy = {},
            make_stub = function() return {} end,
            ensure_wire_safe_funcs = function() end,
            min_thp_on_kill = 1.5,
        })
        H.equal(ok, false)
        H.equal(err, marker)
        H.deep_equal(built, { early = 1, engineer = 1, focused = 0, late = 0 })
    end)

    H.test("CRT balance catalogue rejects Engineer duplicate ownership before later builds", function()
        local path = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/_crt_balance_catalog.lua"
        local build = assert(loadfile(path))()
        local later_builds = 0
        local fake_mod = {}

        function fake_mod:dofile(module_path)
            if module_path:find("_early", 1, true) then
                return function() return { duplicate_setting = {} } end
            end
            if module_path:find("_engineer", 1, true) then
                return function() return { duplicate_setting = {} } end
            end
            return function()
                later_builds = later_builds + 1
                return { later = {} }
            end
        end

        local ok, err = pcall(build, {
            mod = fake_mod,
            wire_policy = {},
            make_stub = function() return {} end,
            ensure_wire_safe_funcs = function() end,
            min_thp_on_kill = 1.5,
        })
        H.equal(ok, false)
        H.truthy(tostring(err):find("duplicate CRT balance definition: duplicate_setting", 1, true))
        H.equal(later_builds, 0)
    end)

    H.test("CRT production catalogue composes all four owners and 76 definitions", function()
        local root = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/"
        local build = assert(loadfile(root .. "_crt_balance_catalog.lua"))()
        local fake_mod = { _crt = { focused_spirit = {} } }

        function fake_mod:dofile(module_path)
            local name = assert(module_path:match("([^/]+)$"))
            return assert(loadfile(root .. name .. ".lua"))()
        end

        local result = build({
            mod = fake_mod,
            wire_policy = {},
            make_stub = function() return {} end,
            ensure_wire_safe_funcs = function() end,
            min_thp_on_kill = 1.5,
        })
        local count = 0
        for _ in pairs(result) do count = count + 1 end
        H.equal(count, 76)
        H.truthy(result.rework_dr_engineer_ingenious_ordnance_240s)
        H.truthy(result.rework_dr_engineer_leading_shots)
        H.truthy(result.rework_dr_engineer_full_head_of_steam_4pct)
    end)
end
