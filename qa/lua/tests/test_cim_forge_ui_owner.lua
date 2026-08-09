return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"

    local function read(name)
        local file = assert(io.open(root .. name, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local entry = read("crafting_in_modded_dev.lua")
    local owner = read("_cim_forge_ui_owner.lua")

    H.test("CIM forge UI owner occupies one exact ordered entry seam", function()
        H.equal(count_plain(entry,
            "scripts/mods/crafting_in_modded_dev/_cim_forge_ui_owner"), 1)
        local properties_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_accessory_property_runtime",
            1, true))
        local owner_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_forge_ui_owner", 1, true))
        local economy_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_weave_economy", 1, true))
        H.truthy(properties_at < owner_at)
        H.truthy(owner_at < economy_at)

        H.equal(count_plain(entry,
            'mod:hook_safe("HeroWindowWeaveProperties", "_draw"'), 0)
        H.equal(count_plain(entry,
            'mod:hook_safe("HeroViewStateWeaveForge", "update"'), 0)
        H.equal(count_plain(owner,
            'mod:hook_safe("HeroWindowWeaveProperties", "_draw"'), 1)
        H.equal(count_plain(owner,
            'mod:hook_safe("HeroViewStateWeaveForge", "update"'), 1)

        local draw_at = assert(owner:find(
            'mod:hook_safe("HeroWindowWeaveProperties", "_draw"', 1, true))
        local update_at = assert(owner:find(
            'mod:hook_safe("HeroViewStateWeaveForge", "update"', 1, true))
        H.truthy(draw_at < update_at)
    end)

    H.test("CIM forge UI owner remains bounded and presentation-only", function()
        local physical = 0
        for _ in owner:gmatch("[^\r\n]+") do physical = physical + 1 end
        H.truthy(physical < 1500, "forge UI owner exceeds 1500-line target")
        H.equal(count_plain(owner, "mod:network_register"), 0)
        H.equal(count_plain(owner, 'mod:hook("BackendInterface'), 0)
        H.equal(count_plain(owner, "_forge_save("), 0)
        H.equal(count_plain(owner, "_modded_loadout"), 0)
        H.equal(count_plain(owner, "set_loadout_item"), 0)
        H.truthy(owner:find("local _AMULET_BTNS_ENABLED = false", 1, true))
        H.truthy(owner:find("local _OVERVIEW_BTNS_ENABLED = false", 1, true))
        H.truthy(owner:find("local _AMULET_PANEL_ENABLED = true", 1, true))
    end)

    H.test("CIM forge UI owner installs once with stable late-bound dispatch", function()
        local install = assert(loadfile(root .. "_cim_forge_ui_owner.lua"))()
        local hooks = {}
        local mod = {
            hook_safe = function(_, class_name, method_name, callback)
                hooks[#hooks + 1] = {
                    class_name = class_name,
                    method_name = method_name,
                    callback = callback,
                }
            end,
            info = function() end,
            warning = function() end,
            echo = function() end,
            get = function() return 300 end,
        }
        local old_draws, new_draws = 0, 0
        local old_panel = { draw = function() old_draws = old_draws + 1 end }
        local new_panel = { draw = function() new_draws = new_draws + 1 end }
        local old_bg, new_bg = false, false
        local old_manager_reads, new_manager_reads = 0, 0
        local old_profile_reads, new_profile_reads = 0, 0
        local old_managers, new_managers = {}, {}
        local old_profiles, new_profiles = {}, {}
        local first, first_installed = install({
            mod = mod,
            accessory_panel = old_panel,
            is_active = function() return false end,
            get_bg_colored = function() return old_bg end,
            set_bg_colored = function(value) old_bg = value end,
            get_managers = function()
                old_manager_reads = old_manager_reads + 1
                return old_managers
            end,
            get_profiles = function()
                old_profile_reads = old_profile_reads + 1
                return old_profiles
            end,
        })
        local second, second_installed = install({
            mod = mod,
            accessory_panel = new_panel,
            is_active = function() return true end,
            get_bg_colored = function() return new_bg end,
            set_bg_colored = function(value) new_bg = value end,
            get_managers = function()
                new_manager_reads = new_manager_reads + 1
                return new_managers
            end,
            get_profiles = function()
                new_profile_reads = new_profile_reads + 1
                return new_profiles
            end,
        })

        H.equal(first_installed, true)
        H.equal(second_installed, false)
        H.equal(first, second)
        H.equal(#hooks, 2)
        H.equal(hooks[1].class_name, "HeroWindowWeaveProperties")
        H.equal(hooks[1].method_name, "_draw")
        H.equal(hooks[2].class_name, "HeroViewStateWeaveForge")
        H.equal(hooks[2].method_name, "update")
        H.equal(mod._cim_forge_ui_owner_installed, true)
        H.equal(first.install_count, 1)
        H.equal(first.apply_ui_polish, second.apply_ui_polish)
        H.equal(first.get_widget, second.get_widget)

        local export_keys = {}
        for key in pairs(second) do export_keys[#export_keys + 1] = key end
        table.sort(export_keys)
        H.equal(table.concat(export_keys, ","),
            "apply_ui_polish,get_widget,install_count")

        H.truthy(old_panel._on_craft, "first panel did not receive craft callback")
        H.equal(new_panel._on_craft, old_panel._on_craft,
            "fresh panel did not receive the stable craft callback")

        local properties_win = {
            _params = {},
            _ui_top_renderer = {},
            _parent = { window_input_service = function() return "fresh-input" end },
        }
        hooks[1].callback(properties_win, 0)
        H.equal(old_draws, 0, "draw hook retained the stale panel")
        H.equal(new_draws, 1, "draw hook did not consume the fresh panel")
        H.equal(new_panel._properties_win, properties_win)

        local crafted = nil
        mod._cim_amulet_craft_one_slot = function(window, slot_index, slot_name)
            crafted = { window, slot_index, slot_name }
        end
        new_panel._on_craft(2, "slot_necklace")
        H.equal(crafted[1], properties_win)
        H.equal(crafted[2], 2)
        H.equal(crafted[3], "slot_necklace")

        hooks[2].callback({
            _active_windows = {
                { NAME = "HeroWindowWeaveForgeBackground", _widgets_by_name = {} },
            },
        }, 0, 0)
        H.equal(old_bg, false, "registered callback retained stale setter")
        H.equal(new_bg, true, "registered callback did not consume refreshed setter")
        H.equal(old_manager_reads, 0, "registered callback retained stale Managers accessor")
        H.equal(old_profile_reads, 0, "registered callback retained stale profiles accessor")
        H.equal(new_manager_reads, 1, "registered callback missed fresh Managers accessor")
        H.equal(new_profile_reads, 1, "registered callback missed fresh profiles accessor")
    end)

    H.test("CIM forge UI owner receives mutable state through explicit accessors", function()
        for _, dependency in ipairs({
            "is_active", "get_bg_colored", "set_bg_colored",
            "get_managers", "get_profiles", "accessory_panel",
        }) do
            H.truthy(entry:find(dependency .. " =", 1, true),
                "entry does not inject " .. dependency)
            H.truthy(owner:find("ctx." .. dependency, 1, true),
                "owner does not consume " .. dependency)
        end
        H.truthy(owner:find("state.is_active()", 1, true))
        H.truthy(owner:find("state.get_bg_colored()", 1, true))
        H.truthy(owner:find("state.set_bg_colored(true)", 1, true))
    end)

    H.test("CIM forge UI owner recovers when the optional panel loads after install", function()
        local install = assert(loadfile(root .. "_cim_forge_ui_owner.lua"))()
        local hooks = {}
        local mod = {
            hook_safe = function(_, class_name, method_name, callback)
                hooks[#hooks + 1] = {
                    class_name = class_name,
                    method_name = method_name,
                    callback = callback,
                }
            end,
            info = function() end,
            warning = function() end,
            echo = function() end,
            get = function() return 300 end,
        }
        local active = true
        local function context(panel)
            return {
                mod = mod,
                accessory_panel = panel,
                is_active = function() return active end,
                get_bg_colored = function() return false end,
                set_bg_colored = function() end,
                get_managers = function() return {} end,
                get_profiles = function() return {} end,
            }
        end

        local _, first_installed = install(context(nil))
        H.equal(first_installed, true)
        H.equal(#hooks, 2, "optional panel failure changed hook cardinality")
        hooks[1].callback({ _params = {} }, 0)

        local draws = 0
        local fresh_panel = { draw = function() draws = draws + 1 end }
        local _, second_installed = install(context(fresh_panel))
        H.equal(second_installed, false)
        H.equal(#hooks, 2, "panel recovery registered a duplicate hook")
        H.truthy(fresh_panel._on_craft, "recovered panel did not receive craft callback")

        local properties_win = { _params = {}, _ui_top_renderer = {} }
        hooks[1].callback(properties_win, 0)
        H.equal(draws, 1)
        H.equal(fresh_panel._properties_win, properties_win)
    end)
end
