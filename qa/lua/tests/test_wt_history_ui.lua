-- Deterministic #1436 WT history menu, localization, and data-surface coverage.
--
-- This module keeps the presentation-only cases together while preserving their
-- original registration point in test_wt_history.lua.

local function register(H, context)
    local CatalogUI = assert(context.CatalogUI)
    local count_plain = assert(context.count_plain)
    local generated_catalogs = assert(context.generated_catalogs)
    local load_default_catalog = assert(context.load_default_catalog)
    local read_file = assert(context.read_file)
    local repo_root = assert(context.repo_root)
    local script_root = assert(context.script_root)

    H.test("WT #1436 menu and localization share the composite family catalog", function()
        local catalog = load_default_catalog(CatalogUI, script_root)
        local group = assert(CatalogUI.build_widgets(catalog))
        local loc = assert(CatalogUI.build_localization(catalog))
        H.equal(group.setting_id, "wt_history_patch_versions")
        H.equal(#group.sub_widgets, #catalog.families)
        H.truthy(loc.wt_history_patch_versions_description.en
            :find("historical balance projection", 1, true) ~= nil)
        H.truthy(loc.wt_history_state_3_1_0.en
            :find("bounded patch delta", 1, true) ~= nil)
        H.truthy(loc.wt_history_state_5_1_1.en
            :find("bounded patch delta", 1, true) == nil,
            "complete direct historical baseline must not be mislabeled as adjacent")
        for index, family in ipairs(catalog.families) do
            local widget = group.sub_widgets[index]
            H.equal(widget.setting_id, family.setting_id)
            H.equal(widget.default_value, "current")
            H.equal(widget.options[1].value, "current")
            H.equal(widget.options[1].text, "wt_history_state_current")
            H.equal(#widget.options, #family.state_order + 1)
            H.equal(loc[family.setting_id].en, family.display_name)
            H.truthy(loc[family.setting_id .. "_description"].en
                :find("restart", 1, true) ~= nil)
            if family.id == "deepwood_staff" then
                H.truthy(loc[family.setting_id .. "_description"].en
                    :find("hosting or playing solo", 1, true) ~= nil)
            end
            if family.id == "kerillian_swiftbow" then
                H.equal(#widget.options, 2)
                H.equal(widget.options[2].value, "6_10_0_swiftbow_ammunition")
                H.equal(loc[widget.options[2].text].en,
                    "Game Version 6.10.0 (Ammunition Only) - bounded patch delta")
                H.equal(loc.wt_history_state_6_10_0.en,
                    "Game Version 6.10.0 - bounded patch delta",
                    "Swiftbow qualification must not alter existing family labels")
            end
        end
    end)

    H.test("WT #1436 data decoration inserts one history group and fails closed", function()
        local by_path = generated_catalogs(CatalogUI, script_root)
        local loads = 0
        local mod = {}
        function mod:dofile(path)
            loads = loads + 1
            return assert(by_path[path], "unexpected generated module " .. tostring(path))
        end
        local first = { setting_id = "first" }
        local second = { setting_id = "second" }
        local data = { options = { widgets = { first, second } } }

        H.equal(CatalogUI.decorate_menu(mod, data), data)
        H.equal(data.options.widgets[1], first)
        H.equal(data.options.widgets[2].setting_id, "wt_history_patch_versions")
        H.equal(#data.options.widgets[2].sub_widgets, 27)
        H.equal(data.options.widgets[3], second)
        H.equal(loads, 14)
        H.equal(CatalogUI.decorate_menu(mod, data), data)
        H.equal(#data.options.widgets, 3)
        H.equal(loads, 14, "re-decoration must not reload or duplicate the group")

        local malformed = { options = {} }
        H.equal(CatalogUI.decorate_menu(mod, malformed), malformed)
        H.equal(loads, 14, "malformed menu data must not load generated catalogs")
    end)

    H.test("WT #1436 public and dev data surfaces return one index-two history group", function()
        local streams = {
            {
                namespace = "weapon_tweaker",
                root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/",
            },
            {
                namespace = "weapon_tweaker_dev",
                root = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/",
            },
        }
        for _, stream in ipairs(streams) do
            local data_path = stream.root .. stream.namespace .. "_data.lua"
            local source = read_file(data_path)
            local module_path = "scripts/mods/" .. stream.namespace
                .. "/_wt_history_catalog"
            local exact_return = "return mod:dofile(\"" .. module_path
                .. "\").decorate_menu(mod, data)"
            H.equal(count_plain(source, exact_return), 1,
                stream.namespace .. " must delegate its final return exactly once")
            H.truthy(source:match(exact_return:gsub("([^%w])", "%%%1") .. "%s*$") ~= nil,
                stream.namespace .. " history decoration must remain the final return")

            local catalog_ui = assert(loadfile(stream.root
                .. "_wt_history_catalog.lua"))()
            local by_path = generated_catalogs(catalog_ui, stream.root)
            local loads = 0
            local mod = {}
            function mod:dofile(path)
                loads = loads + 1
                return assert(by_path[path],
                    "unexpected generated module " .. tostring(path))
            end
            local availability = { setting_id = "weapon_availability" }
            local overrides = { setting_id = "weapon_overrides" }
            local data = { options = { widgets = { availability, overrides } } }
            H.equal(catalog_ui.decorate_menu(mod, data), data)
            H.equal(data.options.widgets[1], availability)
            H.equal(data.options.widgets[2].setting_id,
                "wt_history_patch_versions")
            H.equal(#data.options.widgets[2].sub_widgets, 27)
            H.equal(data.options.widgets[3], overrides)
            H.equal(loads, 14)
            H.equal(catalog_ui.decorate_menu(mod, data), data)
            H.equal(#data.options.widgets, 3,
                stream.namespace .. " must not duplicate its history group")
            H.equal(loads, 14,
                stream.namespace .. " must reuse its generated-catalog cache")
        end
    end)
end

return register
