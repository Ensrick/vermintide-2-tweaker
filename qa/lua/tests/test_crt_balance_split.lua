return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
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
        local late = read(root .. "_crt_balance_catalog_late.lua")

        H.truthy(balance:find(
            'mod:dofile("scripts/mods/career_tweaker/_crt_balance_catalog")',
            1, true))
        H.equal(balance:find("local BALANCE_MODS = {", 1, true), nil)
        H.truthy(early:find("local BALANCE_MODS = {", 1, true))
        H.truthy(late:find("local BALANCE_MODS = {", 1, true))
        H.truthy(catalog:find("local function build(ctx)", 1, true))
        H.truthy(catalog:find(
            'mod:dofile("scripts/mods/career_tweaker/_crt_balance_catalog_early")',
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
        H.truthy(late:find("return BALANCE_MODS", 1, true))
        H.equal(catalog:find("mod:hook(", 1, true), nil,
            "the catalogue composer must remain hook-neutral")
        H.equal(early:find("mod:hook(", 1, true), nil,
            "the early declarative catalogue must remain hook-neutral")
        H.equal(late:find("mod:hook(", 1, true), nil,
            "the late declarative catalogue must remain hook-neutral")
    end)

    H.test("CRT balance catalogue composer merges disjoint owners and rejects collisions", function()
        local path = repo_root .. "/career_tweaker/scripts/mods/career_tweaker/_crt_balance_catalog.lua"
        local build = assert(loadfile(path))()
        local function context(late_definitions)
            local fake_mod = {}
            function fake_mod:dofile(module_path)
                if module_path:find("_early", 1, true) then
                    return function() return { early_setting = { character = "markus" } } end
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
        H.truthy(composed.late_setting)

        local ok, err = pcall(build, context({ early_setting = { character = "bardin" } }))
        H.equal(ok, false)
        H.truthy(tostring(err):find("duplicate CRT balance definition", 1, true))
    end)
end
