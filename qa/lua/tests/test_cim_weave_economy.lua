return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local module_path = root .. "_cim_weave_economy.lua"
    local entry_path = root .. "crafting_in_modded_dev.lua"

    local function read(path)
        local file = assert(io.open(path, "rb"))
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

    local expected_order = {
        "get_forge_level",
        "get_essence",
        "get_maximum_essence",
        "get_total_essence",
        "get_property_required_forge_level",
        "get_property_mastery_costs",
        "get_trait_required_forge_level",
        "get_talent_required_forge_level",
        "get_trait_mastery_cost",
        "get_talent_mastery_cost",
        "get_career_magic_level",
        "get_item_magic_level",
        "max_magic_level",
        "forge_magic_level_cap",
        "magic_item_cost",
        "get_average_power_level",
        "magic_item_upgrade_cost",
        "career_upgrade_cost",
    }

    local function fixture(active)
        local hooks, order = {}, {}
        local mod = {}
        function mod:hook(class_name, method_name, callback)
            H.equal(class_name, "BackendInterfaceWeavesPlayFab")
            H.equal(hooks[method_name], nil, "duplicate hook " .. method_name)
            hooks[method_name] = callback
            order[#order + 1] = method_name
        end

        local install = assert(loadfile(module_path))()
        local installed = install({
            mod = mod,
            is_active = function() return active.value end,
            bubble_cap = function(property_name)
                H.equal(property_name, "weave_attack_speed")
                return 7
            end,
            build_zero_mastery_costs = function(cap)
                return { marker = "zero-costs", cap = cap }
            end,
        })
        return mod, hooks, order, install, installed
    end

    H.test("CIM Weaves economy owner is wired once after forge update", function()
        local entry = read(entry_path)
        H.equal(count_plain(entry,
            "scripts/mods/crafting_in_modded_dev/_cim_weave_economy"), 1)
        H.equal(count_plain(entry,
            'mod:hook("BackendInterfaceWeavesPlayFab", "get_forge_level"'), 0)

        local ui_owner_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_forge_ui_owner", 1, true))
        local owner_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_weave_economy", 1, true))
        local immutable_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_immutable_relic_ui", 1, true))
        H.truthy(ui_owner_at < owner_at)
        H.truthy(owner_at < immutable_at)
        H.truthy(entry:find(
            "bubble_cap = function(property_name) return _bubble_cap(property_name) end",
            1, true), "forward-declared bubble cap must be resolved at hook call time")
    end)

    H.test("CIM Weaves economy installs exact hook order once", function()
        local active = { value = true }
        local mod, hooks, order, install, installed = fixture(active)
        H.equal(installed, true)
        H.deep_equal(order, expected_order)
        H.equal(#order, 18)

        local reloaded_active = { value = false }
        local second = install({
            mod = mod,
            is_active = function() return reloaded_active.value end,
            bubble_cap = function() return 99 end,
            build_zero_mastery_costs = function() return {} end,
        })
        H.equal(second, false)
        H.equal(#order, 18)
        H.equal(type(hooks.get_forge_level), "function")
        H.equal(hooks.get_forge_level(function() return "native" end, {}),
            "native", "reload must refresh accessors without adding hooks")
    end)

    H.test("CIM Weaves economy active facade preserves all fake values", function()
        local active = { value = true }
        local _, hooks = fixture(active)
        local fallback_calls = 0
        local fallback = function()
            fallback_calls = fallback_calls + 1
            return "native"
        end
        local self = {}

        local expected = {
            get_forge_level = 999,
            get_essence = 999999,
            get_maximum_essence = 999999,
            get_total_essence = 999999,
            get_property_required_forge_level = 0,
            get_trait_required_forge_level = 0,
            get_talent_required_forge_level = 0,
            get_trait_mastery_cost = 0,
            get_talent_mastery_cost = 0,
            get_career_magic_level = 999,
            get_item_magic_level = 999,
            max_magic_level = 999,
            forge_magic_level_cap = 999,
            magic_item_cost = 0,
            get_average_power_level = 300,
            magic_item_upgrade_cost = 0,
            career_upgrade_cost = 0,
        }
        for method_name, value in pairs(expected) do
            H.equal(hooks[method_name](fallback, self, "arg1", "arg2"), value,
                method_name)
        end
        H.deep_equal(
            hooks.get_property_mastery_costs(fallback, self,
                "weave_attack_speed"),
            { marker = "zero-costs", cap = 7 })
        H.equal(fallback_calls, 0)
    end)

    H.test("CIM Weaves economy inactive facade preserves native calls", function()
        local active = { value = false }
        local _, hooks = fixture(active)
        local self = {}
        for _, method_name in ipairs(expected_order) do
            local seen = nil
            local function fallback(...)
                seen = { ... }
                return "native-" .. method_name
            end
            H.equal(hooks[method_name](fallback, self, "arg1", "arg2"),
                "native-" .. method_name, method_name)
            H.equal(seen[1], self, method_name .. " self")
            if method_name == "get_property_mastery_costs"
                or method_name == "get_property_required_forge_level"
                or method_name == "get_trait_required_forge_level"
                or method_name == "get_talent_required_forge_level"
                or method_name == "get_trait_mastery_cost"
                or method_name == "get_talent_mastery_cost"
                or method_name == "get_career_magic_level"
                or method_name == "get_item_magic_level"
                or method_name == "magic_item_cost"
                or method_name == "get_average_power_level" then
                H.equal(seen[2], "arg1", method_name .. " arg1")
            elseif method_name == "magic_item_upgrade_cost"
                or method_name == "career_upgrade_cost" then
                H.equal(seen[2], "arg1", method_name .. " arg1")
                H.equal(seen[3], "arg2", method_name .. " arg2")
            else
                H.equal(#seen, 1, method_name .. " arity")
            end
        end
    end)

    H.test("CIM Weaves economy retains bounded native error fallbacks", function()
        local active = { value = false }
        local _, hooks = fixture(active)
        local explode = function() error("native failure") end
        local self = {}
        H.equal(hooks.get_career_magic_level(explode, self, "career"), 0)
        H.equal(hooks.get_item_magic_level(explode, self, "item"), 0)
        H.equal(hooks.get_average_power_level(explode, self, "career"), 300)
        H.equal(hooks.magic_item_upgrade_cost(explode, self, 1, "item"), 0)
        H.equal(hooks.career_upgrade_cost(explode, self, 1, "career"), 0)
    end)
end
