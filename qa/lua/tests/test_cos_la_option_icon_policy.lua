return function(H, repo_root)
    local cos_root = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local policy = dofile(cos_root .. "_cos_la_option_icon_policy.lua")
    local presentation = dofile(cos_root .. "_cos_item_presentation.lua")

    local function read(name)
        local f = assert(io.open(cos_root .. name, "rb"))
        local source = f:read("*a")
        f:close()
        return source
    end

    local function production_option_resolver(environment)
        local source = read("cosmetics_tweaker.lua")
        local first = assert(source:find(
            "local function _cos_option_for_record", 1, true))
        local last = assert(source:find(
            "\nlocal function _cos_primary_component_name", first, true))
        local body = source:sub(first, last - 1)
        body = body:gsub(
            "local function _cos_option_for_record",
            "return function", 1)
        local chunk = assert(loadstring(body))
        setmetatable(environment, { __index = _G })
        setfenv(chunk, environment)
        return chunk()
    end

    local function normalize(item_type)
        if item_type == "es_sword_shield_breton" then
            return "es_1h_sword_shield_breton"
        end
        return item_type
    end

    local kotbs = "Kruber_empire_shield_hero1_Kotbs01"
    local skin_list = {
        [kotbs] = {
            icons = {
                es_1h_mace_shield_skin_01 =
                    "kruber_empire_shield_hero1_kotbs01_mace_icon",
                es_deus_01_skin_01 =
                    "kruber_empire_shield_hero1_kotbs01_spear_icon",
                es_1h_sword_shield_skin_03_runed_01 =
                    "kruber_empire_shield_hero1_kotbs01_sword_icon",
                es_1h_sword_shield_skin_03_runed_02 =
                    "kruber_empire_shield_hero1_kotbs01_sword_icon",
            },
        },
    }

    H.test("LA target options are immutable per weapon family (#923)", function()
        local fields = {
            name = "Kotbs01",
            armoury_key = kotbs,
            intended_unit = "units/kotbs",
        }
        local mace = policy.new_target_option(fields, "es_1h_mace_shield")
        local spear = policy.new_target_option(fields, "es_deus_01")
        H.truthy(mace ~= spear)
        H.equal(mace.target_item_type, "es_1h_mace_shield")
        H.equal(spear.target_item_type, "es_deus_01")
        H.equal(mace.vanilla_skin, nil)
        H.equal(mace.inventory_icon, nil)
        H.equal(mace.cos_authored, false)
    end)

    H.test("Kotbs mace and spear resolve their distinct exact LA icons (#923)", function()
        local base = policy.new_target_option({
            name = "Kotbs01", armoury_key = kotbs,
        }, "es_1h_mace_shield")
        base.la_armoury_key = base.armoury_key
        local mace, mace_reason = policy.resolve_for_item(base,
            "es_1h_mace_shield", "es_1h_mace_shield_skin_01",
            skin_list, normalize)
        H.equal(mace.inventory_icon,
            "kruber_empire_shield_hero1_kotbs01_mace_icon")
        H.equal(mace.vanilla_skin, "es_1h_mace_shield_skin_01")
        H.equal(mace_reason, "exact-skin")

        local spear_base = policy.new_target_option({
            name = "Kotbs01", armoury_key = kotbs,
        }, "es_deus_01")
        spear_base.la_armoury_key = spear_base.armoury_key
        local spear = policy.resolve_for_item(spear_base, "es_deus_01",
            "es_deus_01_skin_01", skin_list, normalize)
        H.equal(spear.inventory_icon,
            "kruber_empire_shield_hero1_kotbs01_spear_icon")
        H.equal(base.inventory_icon, nil)
    end)

    H.test("exact runed skin mapping is not collapsed to a representative icon", function()
        H.equal(skin_list[kotbs].icons.es_1h_sword_shield_skin_03_runed_01,
            "kruber_empire_shield_hero1_kotbs01_sword_icon")
        H.equal(skin_list[kotbs].icons.es_1h_sword_shield_skin_03_runed_02,
            "kruber_empire_shield_hero1_kotbs01_sword_icon")
        local distinct_skin_list = {
            [kotbs] = {
                icons = {
                    es_1h_sword_shield_skin_03_runed_01 =
                        "provider_blue_runed_icon",
                    es_1h_sword_shield_skin_03_runed_02 =
                        "provider_purple_runed_icon",
                },
            },
        }
        local option = policy.new_target_option({
            la_armoury_key = kotbs,
        }, "es_1h_sword_shield")
        local blue = policy.resolve_for_item(option, "es_1h_sword_shield",
            "es_1h_sword_shield_skin_03_runed_01",
            distinct_skin_list, normalize)
        local purple = policy.resolve_for_item(option, "es_1h_sword_shield",
            "es_1h_sword_shield_skin_03_runed_02",
            distinct_skin_list, normalize)
        H.equal(blue.inventory_icon, "provider_blue_runed_icon")
        H.equal(purple.inventory_icon, "provider_purple_runed_icon")
    end)

    H.test("unauthored and sibling targets retain their native icon", function()
        local expanded = policy.new_target_option({
            la_armoury_key = kotbs,
        }, "cwv_es_shield_weapon")
        local resolved, reason = policy.resolve_for_item(expanded,
            "cwv_es_shield_weapon", "cwv_es_shield_weapon_skin_01",
            skin_list, normalize)
        H.equal(resolved.inventory_icon, nil)
        H.equal(resolved.vanilla_skin, nil)
        H.equal(reason, "unmapped-exact-skin")

        local mace = policy.new_target_option({
            la_armoury_key = kotbs,
        }, "es_1h_mace_shield")
        resolved, reason = policy.resolve_for_item(mace,
            "es_1h_mace_shield", "es_deus_01_skin_01",
            skin_list, normalize)
        H.equal(resolved.inventory_icon, nil)
        H.equal(reason, "foreign-skin-family")
    end)

    H.test("_cos_option_for_record keeps native icon after exact LA miss", function()
        local generic_calls = 0
        local external = policy.new_target_option({
            name = "Kotbs01",
            la_armoury_key = kotbs,
            intended_unit = "units/shared_shield",
        }, "cwv_es_shield_weapon")
        local resolver = production_option_resolver({
            ItemMasterList = {},
            _offhand_options = {},
            OFFHAND_NAMES = {
                match_option = function(_, pool) return pool and pool[1] end,
            },
            mod = {
                _ensure_independent_dual_pool = function()
                    return { left_hand_unit = { external } }
                end,
                _la_option_icon_policy = policy,
            },
            get_mod = function()
                return { SKIN_LIST = skin_list }
            end,
            LA_BRIDGE = { normalize_weapon_type = normalize },
            _inventory_icon_for_offhand_unit = function()
                generic_calls = generic_calls + 1
                return "sibling_unit_icon"
            end,
        })
        local resolved = resolver({
            data = { item_type = "cwv_es_shield_weapon" },
            skin = "cwv_es_shield_weapon_skin_01",
        }, { name = "saved", intended_unit = "units/shared_shield" })
        H.equal(resolved.inventory_icon, nil)
        H.equal(generic_calls, 0,
            "external LA miss must not enter generic unit-icon recovery")

        local descriptor = presentation.resolve({
            base_icon = "native_base_icon",
            primary_name = "Primary",
            secondary_option = resolved,
            ownership = "shield",
            local_resource_available = function() return true end,
        })
        H.equal(descriptor.icon, "native_base_icon")
    end)

    H.test("Cosmetics-authored unit options retain generic icon recovery", function()
        local authored = {
            name = "Authored",
            cos_authored = true,
            intended_unit = "units/cos_authored",
        }
        local resolver = production_option_resolver({
            ItemMasterList = {},
            _offhand_options = {},
            OFFHAND_NAMES = {
                match_option = function(_, pool) return pool and pool[1] end,
            },
            mod = {
                _ensure_independent_dual_pool = function()
                    return { left_hand_unit = { authored } }
                end,
                _la_option_icon_policy = policy,
            },
            get_mod = function() return nil end,
            LA_BRIDGE = { normalize_weapon_type = normalize },
            _inventory_icon_for_offhand_unit = function()
                return "cos_authored_icon"
            end,
        })
        local resolved = resolver({
            data = { item_type = "es_1h_sword_shield" },
        }, { name = "saved", intended_unit = "units/cos_authored" })
        H.equal(resolved.inventory_icon, "cos_authored_icon")
    end)

    H.test("pending preview skin outranks stale equipped widget (#923)", function()
        local customization = {
            _previewer = { _item = { skin = "pending_preview_skin" } },
            _illusion_widgets = {
                {
                    content = {
                        skin_key = "stale_equipped_skin",
                        equipped = true,
                        button_hotspot = {},
                    },
                },
                {
                    content = {
                        skin_key = "current_selected_skin",
                        button_hotspot = { is_selected = true },
                    },
                },
            },
        }
        local skin, reason = policy.selected_primary_skin(
            customization, { skin = "backend_skin" })
        H.equal(skin, "pending_preview_skin")
        H.equal(reason, "preview-item")

        customization._previewer = nil
        skin, reason = policy.selected_primary_skin(
            customization, { skin = "backend_skin" })
        H.equal(skin, "current_selected_skin")
        H.equal(reason, "selected-widget")

        customization._illusion_widgets[2].content.button_hotspot.is_selected = false
        skin, reason = policy.selected_primary_skin(
            customization, { skin = "backend_skin" })
        H.equal(skin, "backend_skin")
        H.equal(reason, "backend-item")
    end)

    H.test("primary skin fallback order is backend interface then default", function()
        local skin, reason = policy.selected_primary_skin(
            {}, { backend_id = "bid", key = "weapon" },
            function(item)
                H.equal(item.backend_id, "bid")
                return "interface_skin"
            end, { weapon = "default_skin" })
        H.equal(skin, "interface_skin")
        H.equal(reason, "backend-interface")

        skin, reason = policy.selected_primary_skin(
            {}, { key = "weapon" }, function() return nil end,
            { weapon = "default_skin" })
        H.equal(skin, "default_skin")
        H.equal(reason, "default-skin")
    end)

    H.test("restore lookup requires exact item type hand and Armoury key", function()
        local pools = {
            es_1h_mace_shield = {
                left_hand_unit = {
                    { armoury_key = kotbs, target_item_type = "es_1h_mace_shield" },
                },
            },
            es_deus_01 = {
                left_hand_unit = {
                    { armoury_key = kotbs, target_item_type = "es_deus_01" },
                },
            },
        }
        local index = policy.index_by_target(pools)
        local mace = policy.lookup(index, "es_1h_mace_shield",
            "left_hand_unit", kotbs)
        local spear = policy.lookup(index, "es_deus_01",
            "left_hand_unit", kotbs)
        H.truthy(mace ~= spear)
        H.equal(mace.target_item_type, "es_1h_mace_shield")
        H.equal(spear.target_item_type, "es_deus_01")
        H.equal(policy.lookup(index, "es_1h_sword_shield",
            "left_hand_unit", kotbs), nil)
    end)

    H.test("source does not persist or transmit external provider icon assets", function()
        local source = read("cosmetics_tweaker.lua")
        H.truthy(source:find(
            "inventory_icon = opt.cos_authored and opt.inventory_icon or nil",
            1, true))
        H.truthy(source:find(
            "option = mod._la_option_icon_policy.resolve_for_item(option, item_type",
            1, true))
        H.truthy(source:find(
            "if not external_la and not option.inventory_icon",
            1, true))
        H.truthy(source:find(
            "return mod._la_option_icon_policy.selected_primary_skin(",
            1, true))
        H.equal(source:find(
            'network_send("cos_la_apply", "all", payload, opt.inventory_icon',
            1, true), nil)
    end)
end
