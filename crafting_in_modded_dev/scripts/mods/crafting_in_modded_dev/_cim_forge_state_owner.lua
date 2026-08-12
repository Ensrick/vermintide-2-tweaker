-- Canonical owner of CIM's forged-item registry, persistence, external-trait
-- activation, legacy MIL injection, and backend-ready restoration transaction.

return function(context)
    assert(type(context) == "table", "_cim_forge_state_owner requires context")
    local mod = assert(context.mod, "_cim_forge_state_owner requires mod")
    local rt_register = assert(context.rt_register,
        "_cim_forge_state_owner requires rt_register")
    local print_line = context.print_line or printf
    local resolve_mod = context.get_mod or get_mod
    local get_managers = context.get_managers or function() return Managers end
    local get_item_master_list = context.get_item_master_list
        or function() return ItemMasterList end
    local get_weapon_traits = context.get_weapon_traits
        or function() return rawget(_G, "WeaponTraits") end
    local get_cjson = context.get_cjson or function() return rawget(_G, "cjson") end
    local get_item_helper = context.get_item_helper or function() return ItemHelper end
    local get_athanor_inject_all = context.get_athanor_inject_all
        or function() return nil end
    local get_restore_modded_loadout = context.get_restore_modded_loadout
        or function() return nil end

    local more_items_lib
    local forged_weapons = {}
    local external_trait_providers = {}
    mod._cim_custom_glow_notice = mod:dofile(
        "scripts/mods/crafting_in_modded_dev/_cim_custom_glow_notice").new()

    local function external_provider_availability()
        local available = {}
        for provider_id, spec in pairs(external_trait_providers) do
            local active = spec and spec.available == true
            if spec and type(spec.is_available) == "function" then
                local ok, result = pcall(spec.is_available)
                active = ok and result == true
            end
            available[provider_id] = active
        end
        return available
    end

    local function partition_external_traits(record, source_parked)
        local policy = mod._cim_external_trait_policy
        if type(record) ~= "table" or type(policy) ~= "table" then return false end
        local combined = policy.merge_traits(record.traits,
            source_parked or record.external_traits)
        local active, parked = policy.partition(combined,
            external_provider_availability())
        record.traits = active
        record.trait = active[1]
        record.external_traits = parked
        return true
    end

    local function detect_mil()
        if more_items_lib then return true end
        local ok, library = pcall(resolve_mod, "MoreItemsLibrary")
        if ok and library then
            more_items_lib = library
            return true
        end
        return false
    end

    local function save()
        local save_data = {}
        for backend_id, weapon in pairs(forged_weapons) do
            save_data[backend_id] = {
                schema_version = weapon.schema_version,
                owner = weapon.owner,
                provider = weapon.provider,
                slot_type = weapon.slot_type,
                item_key = weapon.item_key,
                properties = weapon.properties,
                trait = weapon.trait,
                traits = weapon.traits,
                external_traits = weapon.external_traits,
                skin = weapon.skin,
                power_level = weapon.power_level or 300,
                rarity = weapon.rarity,
                via_mirror = weapon.via_mirror,
                rerolled_props_indices = weapon.rerolled_props_indices,
                rerolled_trait_indices = weapon.rerolled_trait_indices,
                custom_glow = weapon.custom_glow,
            }
        end
        mod:set("forged_weapons", save_data)
    end

    local function load()
        local save_data = mod:get("forged_weapons")
        if not save_data or type(save_data) ~= "table" then return end
        forged_weapons = {}
        for backend_id, weapon in pairs(save_data) do
            local via_mirror = weapon.via_mirror
            if via_mirror == nil then
                via_mirror = weapon.rarity == "promo"
                    or weapon.rarity == "modded"
            end
            local rarity = weapon.rarity == "promo" and "modded"
                or weapon.rarity
            local contract = mod._cim_synthetic_item_contract
            local normalized, err = contract.gate_record("mirror_restore",
                backend_id, {
                    item_key = weapon.item_key,
                    slot_type = weapon.slot_type,
                    properties = weapon.properties or {},
                    trait = weapon.trait,
                    traits = weapon.traits,
                    skin = weapon.skin,
                    power_level = weapon.power_level or 300,
                    rarity = rarity,
                    via_mirror = via_mirror,
                    rerolled_props_indices = weapon.rerolled_props_indices,
                    rerolled_trait_indices = weapon.rerolled_trait_indices,
                    custom_glow = weapon.custom_glow,
                })
            if normalized then
                partition_external_traits(normalized, weapon.external_traits)
                forged_weapons[backend_id] = normalized
            else
                print_line("[cim:628] rejected saved synthetic item bid=%s reason=%s",
                    tostring(backend_id), tostring(err))
            end
        end
        local glow_count, should_log = mod._cim_custom_glow_notice:observe(
            forged_weapons, resolve_mod)
        if should_log then
            pcall(print_line,
                "[cim] %d weapon(s) have saved custom_glow blobs that won't apply (Tweaker: Cosmetics not installed); weavebound skin will render with vanilla defaults",
                glow_count)
        end
        save()
    end

    mod._cim_register_craft = function(backend_id, weapon_data)
        local contract = mod._cim_synthetic_item_contract
        local item_key = type(weapon_data) == "table" and weapon_data.item_key
        local item_master_list = get_item_master_list()
        local master = item_key and item_master_list
            and rawget(item_master_list, item_key)
        local entry, err = contract.gate_record("mirror_injection", backend_id,
            weapon_data, master)
        if not entry then
            print_line("[cim:628] rejected synthetic item registration bid=%s key=%s reason=%s",
                tostring(backend_id), tostring(item_key), tostring(err))
            return false, err
        end
        entry.external_traits = type(weapon_data) == "table"
            and weapon_data.external_traits or nil
        partition_external_traits(entry)
        forged_weapons[backend_id] = entry
        save()
        return true, entry
    end

    mod._cim_set_custom_glow = function(backend_id, blob)
        local entry = forged_weapons[backend_id]
        if not entry then return false end
        entry.custom_glow = blob
        save()
        return true
    end

    mod._cim_unregister_craft = function(backend_id)
        if forged_weapons[backend_id] then
            forged_weapons[backend_id] = nil
            save()
        end
    end
    mod._cim_get_craft = function(backend_id) return forged_weapons[backend_id] end
    mod._cim_persist_crafts = save

    mod._cim_register_external_trait_provider = function(provider_id, spec)
        local policy = mod._cim_external_trait_policy
        local trait_key = type(spec) == "table" and spec.trait_key
        local required = type(policy) == "table"
            and policy.REQUIRED_CAPABILITY_BY_PROVIDER
            and policy.REQUIRED_CAPABILITY_BY_PROVIDER[provider_id]
        if type(provider_id) ~= "string" or type(trait_key) ~= "string"
                or not policy
                or policy.RESERVED_PROVIDER_BY_TRAIT[trait_key] ~= provider_id
                or not required or spec.capability ~= required then
            return false, "invalid_provider_contract"
        end
        local weapon_traits = get_weapon_traits()
        if not (weapon_traits and weapon_traits.traits
                and rawget(weapon_traits.traits, trait_key)) then
            return false, "provider_trait_row_missing"
        end
        external_trait_providers[provider_id] = spec
        local installed, reason = policy.add_combination(
            weapon_traits.combinations, spec.category or "melee", trait_key)
        if not installed then return false, reason end

        local managers = get_managers()
        local backend = managers and managers.backend
        local items = backend and backend:get_interface("items")
        local cjson_mod = get_cjson()
        local activated = 0
        for backend_id, record in pairs(forged_weapons) do
            local parked_before = #(record.external_traits or {})
            partition_external_traits(record)
            if parked_before > #(record.external_traits or {}) then
                activated = activated + 1
            end
            local live
            if items then
                pcall(function() live = items:get_item_from_id(backend_id) end)
            end
            if live then
                local traits = {}
                for i, value in ipairs(record.traits or {}) do traits[i] = value end
                live.traits = traits
                if cjson_mod and live.CustomData then
                    live.CustomData.traits = cjson_mod.encode(traits)
                end
            end
        end
        save()
        print_line("[cim:655] external trait provider=%s capability=%s pool=%s activated=%d",
            provider_id, spec.capability, tostring(reason), activated)
        return true, reason, activated
    end

    mod._cim_is_modded_backend_id = function(backend_id)
        return type(backend_id) == "string"
            and forged_weapons[backend_id] ~= nil
    end
    mod._cim_is_modded_item = function(item)
        if not item then return false end
        if item.rarity == "modded" or item.rarity == "promo" then return true end
        return mod._cim_is_modded_backend_id(item.backend_id)
    end

    rt_register("issue628_provider_contract", function()
        local contract = mod._cim_synthetic_item_contract
        if type(contract) ~= "table" then return "synthetic item contract is missing" end
        local item_master_list = get_item_master_list()
        local keys = {
            "cwv_dr_dawi_mace", "cwv_dr_dawi_mace_shield",
            "cwv_dr_dawi_dual_maces", "cwv_es_longsword",
        }
        local checked = 0
        for i = 1, #keys do
            local key = keys[i]
            local master = item_master_list and rawget(item_master_list, key)
            if master then
                checked = checked + 1
                local ok, problems = contract.validate_provider(key, master)
                if not ok then
                    return key .. " incomplete: " .. table.concat(problems, ",")
                end
            end
        end
        local woc = item_master_list and rawget(item_master_list,
            "woc_blightreaper")
        if woc then
            checked = checked + 1
            local ok, problems, provider = contract.validate_provider(
                "woc_blightreaper", woc)
            if ok or provider ~= "woc" or problems[1] ~= "immutable_relic" then
                return "woc_blightreaper was not rejected as an immutable relic"
            end
        end
        if checked == 0 then return "skip: CWV/WOC provider rows are not loaded" end
    end)

    rt_register("issue628_saved_instance_contract", function()
        local contract = mod._cim_synthetic_item_contract
        for backend_id, record in pairs(forged_weapons) do
            if record.schema_version ~= contract.SCHEMA_VERSION
                    or record.owner ~= contract.OWNER
                    or record.backend_id ~= backend_id
                    or type(record.item_key) ~= "string" then
                return "malformed saved instance: " .. tostring(backend_id)
            end
        end
    end)

    rt_register("issue628_identity_resolvers_unified", function()
        local contract = mod._cim_synthetic_item_contract
        local selector = mod._cim_template_selector
        if type(contract) ~= "table"
                or type(contract.canonical_item_key) ~= "function" then
            return "contract canonical_item_key is missing"
        end
        if type(selector) ~= "table" or type(selector.canonical_key) ~= "function" then
            return "template selector is missing"
        end
        local shapes = {
            { backend_id = "cwv_es_longsword_100", key = "es_bastard_sword" },
            { backend_id = "opaque", data = {
                key = "es_bastard_sword", cwv_key = "cwv_es_longsword" } },
            { ItemId = "cwv_dr_dawi_mace", key = "cwv_dr_dawi_mace",
              data = { cwv_key = "cwv_dr_dawi_mace", slot_type = "melee" } },
            { cim_acquisition_key = "cwv_dr_dawi_dual_maces",
              key = "dr_dual_hammers" },
            { ItemInstanceId = "48400000-0000-4000-8000-000000000484",
              key = "es_handgun", CustomData = {
                  cim_acquisition_key = "cwv_es_musket_old",
                  cwv_key = "cwv_es_musket_old" } },
            { ItemId = "es_1h_sword", key = "es_1h_sword" },
        }
        for i = 1, #shapes do
            local item = shapes[i]
            local canonical = contract.canonical_item_key(item)
            local selected = selector.canonical_key(item)
            if canonical ~= selected then
                return "selector/contract identity drift: contract="
                    .. tostring(canonical) .. " selector=" .. tostring(selected)
            end
        end
        if contract.canonical_item_key(shapes[1]) ~= "cwv_es_longsword" then
            return "base-keyed CWV instance did not resolve to its variant"
        end
        local normalized_shapes = {
            { bid = "48400000-0000-4000-8000-000000000484",
              input = { key = "es_handgun", CustomData = {
                  cim_acquisition_key = "cwv_es_musket_old" } },
              expected = "cwv_es_musket_old" },
            { bid = "opaque", input = { key = "es_bastard_sword",
              data = { cwv_key = "cwv_es_longsword" } },
              expected = "cwv_es_longsword" },
            { bid = "cwv_dr_dawi_mace_100", input = { key = "dr_1h_hammer" },
              expected = "cwv_dr_dawi_mace" },
        }
        for i = 1, #normalized_shapes do
            local shape = normalized_shapes[i]
            local record, err = contract.normalize_record(shape.bid, shape.input)
            if not record or record.item_key ~= shape.expected then
                return "normalization/identity drift: expected=" .. shape.expected
                    .. " actual=" .. tostring(record and record.item_key)
                    .. " error=" .. tostring(err)
            end
        end
    end)

    rt_register("issue484_crafted_old_musket_identity", function()
        local contract = mod._cim_synthetic_item_contract
        if type(contract) ~= "table" then return "synthetic item contract missing" end
        local item_master_list = get_item_master_list()
        local master = item_master_list
            and rawget(item_master_list, "cwv_es_musket_old") or {
                cwv_variant = true, slot_type = "ranged",
                can_wield = { "es_mercenary" }, template = "old_musket_template",
                item_type = "cwv_es_musket_old", inventory_icon = "es_handgun_01",
            }
        local backend_id = "48400000-0000-4000-8000-000000000484"
        local record = contract.normalize_record(backend_id, {
            item_key = "cwv_es_musket_old", rarity = "modded",
        }, master)
        if not record then return "Old Musket synthetic record rejected" end
        local payload = contract.build_mirror_payload(record, master,
            function() return "{}" end)
        local custom = payload and payload.CustomData
        if not custom or custom.cim_acquisition_key ~= "cwv_es_musket_old"
                or custom.cwv_key ~= "cwv_es_musket_old" then
            return "mirror payload dropped the exact Old Musket identity"
        end
        local reconstructed = {
            ItemInstanceId = backend_id,
            key = "es_handgun",
            data = { key = "es_handgun" },
            CustomData = custom,
        }
        if contract.canonical_item_key(reconstructed) ~= "cwv_es_musket_old" then
            return "base-shaped reconstructed UUID did not recover Old Musket identity"
        end
        local selector = mod._cim_template_selector
        if not selector or selector.canonical_key(reconstructed)
                ~= "cwv_es_musket_old" then
            return "Athanor/forge selector drifted from the Old Musket identity contract"
        end
    end)

    local create_item = mod:dofile(
        "scripts/mods/crafting_in_modded_dev/_cim_mil_entry_builder")

    local function inject_item(weapon_data, backend_id)
        if not detect_mil() then
            mod:echo("Forge: MoreItemsLibrary not found — install it from the Workshop")
            return false
        end
        local entry = create_item(weapon_data, backend_id)
        if not entry then return false end
        more_items_lib:add_mod_items_to_local_backend({ entry },
            "crafting_in_modded_dev")
        local managers = get_managers()
        if managers and managers.backend then
            local items = managers.backend:get_interface("items")
            if items then items:_refresh() end
        end
        local item_helper = get_item_helper()
        if item_helper and item_helper.mark_backend_id_as_new then
            pcall(item_helper.mark_backend_id_as_new, backend_id)
        end
        return true
    end

    local function inject_all()
        if not detect_mil() then return end
        for backend_id, weapon in pairs(forged_weapons) do
            if not weapon.via_mirror then
                local entry = create_item(weapon, backend_id)
                if entry then
                    more_items_lib:add_mod_items_to_local_backend({ entry },
                        "crafting_in_modded_dev")
                end
            end
        end
        local managers = get_managers()
        if managers and managers.backend then
            local items = managers.backend:get_interface("items")
            if items then items:_refresh() end
        end
    end

    load()

    mod:hook_safe("BackendManagerPlayFab", "_create_interfaces", function()
        load()
        inject_all()
        local athanor_inject_all = get_athanor_inject_all()
        if athanor_inject_all then athanor_inject_all() end
        local restore_modded_loadout = get_restore_modded_loadout()
        if restore_modded_loadout then restore_modded_loadout() end
        local count = 0
        for _ in pairs(forged_weapons) do count = count + 1 end
        mod:info("Forge: restored %d forged crafts", count)
        if mod._cim_autodump_backend_ready then
            pcall(mod._cim_autodump_backend_ready)
        end

        local managers = get_managers()
        local items_iface = managers and managers.backend
            and managers.backend:get_interface("items")
        local mirror = items_iface and items_iface._backend_mirror
        local inventory = mirror and mirror._inventory_items
        if type(inventory) ~= "table" then return end
        local trimmed = 0
        for backend_id, item in pairs(inventory) do
            local properties = item and item.properties
            if type(properties) == "table" then
                local keep_limit = 10
                local property_count = 0
                local keep, kept_keys, dropped_keys = {}, {}, {}
                for key, value in pairs(properties) do
                    property_count = property_count + 1
                    if property_count <= keep_limit then
                        keep[key] = value
                        kept_keys[#kept_keys + 1] = tostring(key)
                    else
                        dropped_keys[#dropped_keys + 1] = tostring(key)
                    end
                end
                if property_count > keep_limit then
                    item.properties = keep
                    if item.CustomData then
                        local cjson_mod = get_cjson()
                        if cjson_mod then
                            item.CustomData.properties = cjson_mod.encode(keep)
                        end
                    end
                    trimmed = trimmed + 1
                    local item_key = item.key or item.ItemId
                        or (item.data and item.data.key) or "<unknown>"
                    mod:info("[trim] %s (bid=%s) kept=[%s] dropped=[%s]",
                        tostring(item_key), tostring(backend_id),
                        table.concat(kept_keys, ","),
                        table.concat(dropped_keys, ","))
                end
            end
        end
        if trimmed > 0 then
            mod:info("[cim] Trimmed %d items exceeding the 10-property grid ceiling.",
                trimmed)
        end
    end)

    return {
        create_item = create_item,
        detect_mil = detect_mil,
        get_forged_weapons = function() return forged_weapons end,
        get_more_items_lib = function() return more_items_lib end,
        inject_all = inject_all,
        inject_item = inject_item,
        load = load,
        save = save,
        set_forged_weapons = function(value)
            forged_weapons = type(value) == "table" and value or {}
        end,
    }
end
