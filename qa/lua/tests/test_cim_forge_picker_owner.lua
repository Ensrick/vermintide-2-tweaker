return function(H, repo_root)
    local root = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/"
    local module_path = root .. "_cim_forge_picker_owner.lua"
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

    local expected_exports = {
        "apply_forge_freedom",
        "ensure_property_twin",
        "ensure_trait_twin",
        "ensure_weave_category_pools",
        "restore_forge_freedom",
    }

    local function fixture(active, settings)
        local hooks, order, prints, warnings = {}, {}, {}, {}
        local globals = {
            WeaveTraits = { categories = {}, traits = {} },
            WeaveProperties = { categories = {}, properties = {} },
            WeaveLoadoutSettings = {
                career = { talent_tree = {} },
            },
            WeaponTraits = { combinations = {}, traits = {} },
            WeaponProperties = { combinations = {}, properties = {} },
            BuffTemplates = {},
        }
        local mod = {}
        function mod:hook(class_name, method_name, callback)
            H.equal(class_name, "HeroWindowWeaveProperties")
            H.equal(hooks[method_name], nil, "duplicate hook " .. method_name)
            hooks[method_name] = callback
            order[#order + 1] = method_name
        end
        function mod:warning(fmt, ...)
            warnings[#warnings + 1] = string.format(fmt, ...)
        end

        local context = {
            mod = mod,
            is_active = function() return active.value end,
            get_global = function(name) return globals[name] end,
            get_setting = function(id) return settings[id] end,
            get_all_trait_entries = function()
                return { { "all_trait" } }
            end,
            get_cw_trait_entries = function(slot_type)
                H.equal(slot_type, "melee")
                return { { "cw_trait" } }
            end,
            get_all_property_keys = function()
                return { "all_property" }
            end,
            print_line = function(fmt, ...)
                prints[#prints + 1] = string.format(fmt, ...)
            end,
        }
        local install = assert(loadfile(module_path))()
        local owner = install(context)
        return {
            mod = mod,
            owner = owner,
            hooks = hooks,
            order = order,
            prints = prints,
            warnings = warnings,
            globals = globals,
            context = context,
            install = install,
        }
    end

    H.test("CIM forge picker owner has complete contract headers and isolation", function()
        local owner = read(module_path)
        for _, header in ipairs({
            "-- OWNER:", "-- RESPONSIBILITY:", "-- PUBLIC SURFACE:",
            "-- INSTALL ORDER:", "-- INVARIANTS:",
            "-- Owned by:", "-- Consumed via:",
        }) do
            H.equal(count_plain(owner, header), 1, header)
        end
        local lines = 0
        for _ in owner:gmatch("[^\r\n]+") do lines = lines + 1 end
        H.truthy(lines < 1500, "forge picker owner must remain below 1,500 lines")
        H.equal(count_plain(owner, "network_register"), 0)
        H.equal(count_plain(owner, "network_send"), 0)
        H.equal(count_plain(owner, "_forged_weapons"), 0)
        H.equal(count_plain(owner, "_forge_loadout"), 0)
    end)

    H.test("CIM entry installs picker owner once at the exact boundary", function()
        local entry = read(entry_path)
        local owner = read(module_path)
        H.equal(count_plain(entry,
            "scripts/mods/crafting_in_modded_dev/_cim_forge_picker_owner"), 1)
        H.equal(count_plain(entry,
            'mod:hook("HeroWindowWeaveProperties", "_setup_menu_options"'), 0)
        H.equal(count_plain(entry,
            'mod:hook("HeroWindowWeaveProperties", "_sync_backend_loadout"'), 0)
        H.equal(count_plain(owner,
            'mod:hook("HeroWindowWeaveProperties", "_setup_menu_options"'), 1)
        H.equal(count_plain(owner,
            'mod:hook("HeroWindowWeaveProperties", "_sync_backend_loadout"'), 1)

        local preview_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_forge_preview_owner", 1, true))
        local picker_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_forge_picker_owner", 1, true))
        local accessory_at = assert(entry:find(
            "scripts/mods/crafting_in_modded_dev/_cim_accessory_property_runtime", 1, true))
        H.truthy(preview_at < picker_at)
        H.truthy(picker_at < accessory_at)
        H.equal(count_plain(entry,
            "_cim_restore_forge_freedom = _forge_picker_owner.restore_forge_freedom"), 1)
    end)

    H.test("CIM picker owner exports exactly five stable operations", function()
        local f = fixture({ value = false }, {})
        local actual = {}
        for key in pairs(f.owner) do actual[#actual + 1] = key end
        table.sort(actual)
        H.deep_equal(actual, expected_exports)
        H.equal(f.mod._cim_forge_picker_owner, f.owner)
        H.equal(f.mod._cim_ensure_weave_category_pools,
            f.owner.ensure_weave_category_pools)
        H.equal(f.mod._cim_ensure_trait_twin, f.owner.ensure_trait_twin)
        H.equal(f.mod._cim_ensure_property_twin, f.owner.ensure_property_twin)
        H.equal(f.mod._cim_apply_forge_freedom, f.owner.apply_forge_freedom)
        H.equal(f.mod._cim_restore_forge_freedom, f.owner.restore_forge_freedom)
    end)

    H.test("CIM picker owner republishes a replaced map without duplicate hooks", function()
        local active = { value = true }
        local f = fixture(active, {})
        H.deep_equal(f.order, { "_setup_menu_options", "_sync_backend_loadout" })
        local first_owner = f.owner

        -- Leave a real transaction outstanding on the first dependency set.
        -- Reload must restore THESE exact tables before it accepts a distinct
        -- globals resolver; replaying the backup into replacement globals would
        -- both pollute new state and strand the old state widened.
        local old_trait_original = { "old_weave_trait" }
        f.globals.WeaveTraits.categories.old_cat = old_trait_original
        f.globals.WeaveProperties.categories.old_prop = nil
        f.globals.WeaponTraits.combinations.old_cat = { { "old_trait" } }
        f.globals.WeaponTraits.traits.old_trait = { display_name = "old trait" }
        f.globals.WeaponProperties.combinations.old_prop = {
            exotic = { { "old_property" } },
        }
        f.globals.WeaponProperties.properties.old_property = {
            display_name = "old property",
            buff_name = "old_property_buff",
            description_values = { { value = 0.2 } },
        }
        f.globals.BuffTemplates.old_property_buff = { buffs = { {} } }
        first_owner.apply_forge_freedom({
            traits = { { category = "old_cat" } },
            properties = { { category = "old_prop" } },
        }, "melee")
        H.truthy(f.globals.WeaveTraits.categories.old_cat ~= old_trait_original)
        H.deep_equal(f.globals.WeaveProperties.categories.old_prop,
            { "weave_old_property" })

        local second_active = { value = false }
        local second_context = {}
        for key, value in pairs(f.context) do second_context[key] = value end
        second_context.is_active = function() return second_active.value end
        local reload_trait_original = {}
        local reload_property_original = {}
        local reloaded_globals = {
            WeaveTraits = {
                categories = { reload_cat = reload_trait_original }, traits = {},
            },
            WeaveProperties = {
                categories = { reload_prop = reload_property_original }, properties = {},
            },
            WeaponTraits = {
                combinations = { reload_cat = {} },
                traits = { reload_trait = { display_name = "reload trait" } },
            },
            WeaponProperties = {
                combinations = { reload_prop = { exotic = {} } },
                properties = {
                    reload_property = {
                        display_name = "reload property",
                        buff_name = "reload_property_buff",
                        description_values = { { value = 0.1 } },
                    },
                },
            },
            BuffTemplates = { reload_property_buff = { buffs = { {} } } },
        }
        second_context.get_global = function(name) return reloaded_globals[name] end
        second_context.get_setting = function(id)
            return id == "allow_any_trait_property"
        end
        second_context.get_all_trait_entries = function()
            return { { "reload_trait" } }
        end
        second_context.get_all_property_keys = function()
            return { "reload_property" }
        end
        local replacement = { stale_key = "must be removed" }
        f.mod._cim_forge_picker_owner = replacement
        f.mod._cim_ensure_weave_category_pools = nil
        f.mod._cim_ensure_trait_twin = nil
        f.mod._cim_ensure_property_twin = nil
        f.mod._cim_apply_forge_freedom = nil
        f.mod._cim_restore_forge_freedom = nil
        local second_owner = f.install(second_context)
        H.equal(f.globals.WeaveTraits.categories.old_cat, old_trait_original,
            "reload must restore the exact old trait-category table")
        H.equal(f.globals.WeaveProperties.categories.old_prop, nil,
            "reload must restore old category absence on the old globals")
        H.equal(reloaded_globals.WeaveTraits.categories.reload_cat,
            reload_trait_original,
            "reload must not replay an old backup into new trait globals")
        H.equal(reloaded_globals.WeaveProperties.categories.reload_prop,
            reload_property_original,
            "reload must not replay an old backup into new property globals")
        H.equal(second_owner, replacement,
            "installer must republish into the genuinely replaced public map")
        H.truthy(second_owner ~= first_owner,
            "public namespace identity is replaceable across reload")
        local actual = {}
        for key in pairs(second_owner) do actual[#actual + 1] = key end
        table.sort(actual)
        H.deep_equal(actual, expected_exports,
            "replacement map must contain exactly the five owner operations")
        H.equal(f.mod._cim_ensure_weave_category_pools,
            second_owner.ensure_weave_category_pools)
        H.equal(f.mod._cim_ensure_trait_twin, second_owner.ensure_trait_twin)
        H.equal(f.mod._cim_ensure_property_twin, second_owner.ensure_property_twin)
        H.equal(f.mod._cim_apply_forge_freedom,
            second_owner.apply_forge_freedom)
        H.equal(f.mod._cim_restore_forge_freedom,
            second_owner.restore_forge_freedom)
        H.deep_equal(f.order, { "_setup_menu_options", "_sync_backend_loadout" })

        local native_calls = 0
        local result = f.hooks._sync_backend_loadout(function(self)
            native_calls = native_calls + 1
            return self.marker
        end, { marker = "native" })
        H.equal(result, "native", "installed callback must consume refreshed active accessor")
        H.equal(native_calls, 1)

        second_active.value = true
        local setup_calls = 0
        f.hooks._setup_menu_options(function()
            setup_calls = setup_calls + 1
            return "setup-native"
        end, {
            _selected_item = function()
                return { data = { slot_type = "melee" } }
            end,
        }, "career", {
            traits = { { category = "reload_cat" } },
            properties = { { category = "reload_prop" } },
        })
        H.equal(setup_calls, 1)
        H.deep_equal(reloaded_globals.WeaveTraits.categories.reload_cat,
            { "weave_reload_trait" },
            "installed hook must consume refreshed trait/global dependencies")
        H.deep_equal(reloaded_globals.WeaveProperties.categories.reload_prop,
            { "weave_reload_property" },
            "installed hook must consume refreshed property/global dependencies")
        second_owner.restore_forge_freedom()
        H.equal(reloaded_globals.WeaveTraits.categories.reload_cat,
            reload_trait_original,
            "new transaction must restore its exact trait-category table")
        H.equal(reloaded_globals.WeaveProperties.categories.reload_prop,
            reload_property_original,
            "new transaction must restore its exact property-category table")
    end)

    H.test("CIM picker owner seeds only progression categories", function()
        local f = fixture({ value = false }, {})
        f.owner.ensure_weave_category_pools("career", {
            traits = { { category = "trait_cat" }, { category = "trait_cat" } },
            properties = { { category = "property_cat" } },
            talents = { { category = "talent_cat" } },
        })
        H.deep_equal(f.globals.WeaveTraits.categories.trait_cat, {})
        H.deep_equal(f.globals.WeaveProperties.categories.property_cat, {})
        H.deep_equal(
            f.globals.WeaveLoadoutSettings.career.talent_tree.talent_cat, {})
        H.equal(f.globals.WeaveTraits.categories.unrelated, nil)
    end)

    H.test("CIM picker owner creates valid matched trait and property twins", function()
        local f = fixture({ value = false }, {})
        f.globals.WeaponTraits.traits.native_trait = {
            display_name = "trait_name",
            icon = "trait_icon",
            buff_name = "trait_buff",
            advanced_description = "trait_desc",
            description_values = { { value = 1 } },
        }
        f.globals.WeaponProperties.properties.native_property = {
            display_name = "property_name",
            buff_name = "property_buff",
        }
        f.globals.BuffTemplates.property_buff = { buffs = { {} } }

        H.equal(f.owner.ensure_trait_twin("native_trait"), "weave_native_trait")
        local trait = f.globals.WeaveTraits.traits.weave_native_trait
        H.equal(trait.advanced_description, "trait_desc")
        H.deep_equal(trait.description_values, { { value = 1 } })
        H.equal(f.owner.ensure_property_twin("native_property"),
            "weave_native_property")
        local property = f.globals.WeaveProperties.properties.weave_native_property
        H.equal(property.icon, "icons_placeholder")
        H.equal(property.category, "offensive")
        H.equal(property.description_values[1].value, 0.05)
        H.equal(f.owner.ensure_property_twin("missing"), nil)
    end)

    H.test("CIM picker owner widens from native pools and restores exact originals", function()
        local settings = { allow_cw_traits = true, allow_any_trait_property = false }
        local f = fixture({ value = true }, settings)
        local original_traits = { "existing_weave_trait" }
        f.globals.WeaveTraits.categories.weapon_cat = original_traits
        f.globals.WeaveProperties.categories.weapon_prop = nil
        f.globals.WeaponTraits.combinations.weapon_cat = { { "native_trait" } }
        f.globals.WeaponTraits.traits.native_trait = { display_name = "native" }
        f.globals.WeaponTraits.traits.cw_trait = { display_name = "cw" }
        f.globals.WeaponProperties.combinations.weapon_prop = {
            exotic = { { "native_property" } },
        }
        f.globals.WeaponProperties.properties.native_property = {
            display_name = "native property", buff_name = "native_property_buff",
            description_values = { { value = 0.1 } },
        }
        f.globals.BuffTemplates.native_property_buff = { buffs = { {} } }

        f.owner.apply_forge_freedom({
            traits = { { category = "weapon_cat" }, { category = "weapon_cat" } },
            properties = { { category = "weapon_prop" } },
        }, "melee")
        H.deep_equal(f.globals.WeaveTraits.categories.weapon_cat, {
            "existing_weave_trait", "weave_native_trait", "weave_cw_trait",
        })
        H.deep_equal(f.globals.WeaveProperties.categories.weapon_prop, {
            "weave_native_property",
        })

        f.owner.restore_forge_freedom()
        H.equal(f.globals.WeaveTraits.categories.weapon_cat, original_traits,
            "restore must retain the exact original table")
        H.equal(f.globals.WeaveProperties.categories.weapon_prop, nil,
            "category absent before widening must be removed")
    end)

    H.test("CIM picker hooks preserve active and inactive fallbacks", function()
        local active = { value = false }
        local f = fixture(active, {})
        local native_setup = 0
        local self = {
            _selected_item = function()
                return { data = { slot_type = "melee" } }
            end,
        }
        local result = f.hooks._setup_menu_options(function(_, career, progression)
            native_setup = native_setup + 1
            H.equal(career, "career")
            H.truthy(type(progression) == "table")
            return "setup-native"
        end, self, "career", { traits = { { category = "seeded" } } })
        H.equal(result, "setup-native")
        H.equal(native_setup, 1)
        H.deep_equal(f.globals.WeaveTraits.categories.seeded, {})

        local native_sync = 0
        H.equal(f.hooks._sync_backend_loadout(function()
            native_sync = native_sync + 1
            return "sync-native"
        end, {}), "sync-native")
        H.equal(native_sync, 1)

        active.value = true
        local populated = 0
        f.hooks._sync_backend_loadout(function() error("tooltip failure") end, {
            _populate_menu_widgets = function() populated = populated + 1 end,
        })
        H.equal(populated, 1)
        H.equal(#f.prints, 1)
        H.equal(#f.warnings, 1)
        H.truthy(f.prints[1]:find("tooltip failure", 1, true))
    end)

    H.test("CIM entry injects every forge picker dependency exactly once", function()
        local entry = read(entry_path)
        local owner_at = assert(entry:find("local _forge_picker_owner =", 1, true))
        local owner_end = assert(entry:find("_cim_restore_forge_freedom =",
            owner_at, true))
        local install = entry:sub(owner_at, owner_end + 100)
        for _, dependency in ipairs({
            "is_active", "get_global", "get_setting", "get_all_trait_entries",
            "get_cw_trait_entries", "get_all_property_keys", "print_line",
        }) do
            H.equal(count_plain(install, dependency .. " ="), 1,
                "entry injects " .. dependency)
        end
    end)
end
