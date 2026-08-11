-- _cos_item_presentation_runtime.lua -- exact-instance item-card adapters.
--
-- Owns the engine-facing half of item presentation. Phase one resolves and
-- publishes exact-instance icon/name/description state and installs the one
-- UIUtils hook. Phase two publishes the Hold-Tab peer-cache adapter only after
-- LA transport has installed its receivers. The engine-free descriptor policy
-- remains in _cos_item_presentation.lua.
--
-- This owner adds no RPC, command, lifecycle callback, update loop, durable
-- persistence write, equipment spawn, material mutation, or package load.

local Runtime = {}

local REQUIRED = {
    "composite_icon_factory",
    "la_persist",
    "get_item_master_list",
    "get_weapon_skins",
    "offhand_selection",
    "glow_picker",
    "composite_icons",
    "offhand_names",
    "shield_icon_owner_item_types",
    "offhand_options",
    "get_mod",
    "la_bridge",
    "inventory_icon_for_offhand_unit",
    "item_presentation",
    "la_icon_provider",
    "la_instance_policy",
    "offhand_session_state",
    "get_localize",
}

local function validate(deps)
    assert(type(deps) == "table", "item presentation runtime dependencies are required")
    for _, name in ipairs(REQUIRED) do
        assert(deps[name] ~= nil, name .. " is required")
    end
end

function Runtime.install(mod, deps)
    validate(deps)

    local owner = mod._cos_item_presentation_runtime_owner
    if owner then
        owner.ctx = deps
        return owner
    end

    owner = {
        ctx = deps,
        peer_ctx = nil,
        peer_installed = false,
    }
    mod._cos_item_presentation_runtime_owner = owner

    local function context()
        return owner.ctx
    end

    local function ui_icon_available(icon)
        local ctx = context()
        local Application = ctx.get_application and ctx.get_application() or nil
        return ctx.composite_icon_factory.ui_icon_availability(icon,
            ctx.ui_atlas_helper, Application and Application.can_get)
    end

    local function active_skin(item, backend_id)
        local ctx = context()
        local WeaponSkins = ctx.get_weapon_skins()
        local skin = backend_id and ctx.la_persist
            and ctx.la_persist.get_saved_illusion(backend_id) or nil
        if not skin or skin == "" then skin = item and item.skin end
        local item_key = item and (item.key
            or (item.data and (item.data.name or item.data.key)))
        if (not skin or skin == "") and item_key and WeaponSkins
                and WeaponSkins.default_skins then
            skin = WeaponSkins.default_skins[item_key]
        end
        return skin
    end

    local function resolve_composed_appearance(item, record, publish_for_icon)
        local ctx = context()
        local COMPOSITE_ICONS = ctx.composite_icons
        if type(item) ~= "table" then return nil end
        if publish_for_icon ~= false then COMPOSITE_ICONS.publish(item, nil) end
        local backend_id = item.backend_id or item.ItemInstanceId
        if backend_id == nil then return nil end
        local ItemMasterList = ctx.get_item_master_list()
        local item_data = item.data or (item.key and ItemMasterList
            and rawget(ItemMasterList, item.key))
        local item_type = item_data and item_data.item_type
        local skin = active_skin(item, backend_id)
        if not skin then return nil end

        if record == nil and ctx.la_persist then
            local live = ctx.offhand_selection[backend_id]
            local saved = ctx.la_persist.get_saved_offhands_for(backend_id)
            record = live and live.left_hand_unit
                or (saved and saved.left_hand_unit)
        end
        local offhand_unit = type(record) == "table"
            and (record.unit_path or record.unit or record.intended_unit) or nil
        local offhand_armoury_key = type(record) == "table"
            and (record.armoury_key or record.la_armoury_key) or nil
        if not offhand_unit and not offhand_armoury_key then
            local WeaponSkins = ctx.get_weapon_skins()
            local skin_record = WeaponSkins and WeaponSkins.skins
                and WeaponSkins.skins[skin]
            local skin_data = type(skin_record) == "table"
                and (skin_record.data or skin_record) or nil
            offhand_unit = skin_data and skin_data.left_hand_unit
        end
        local glow_state = ctx.glow_picker.committed_state_for(
            backend_id, { skin = skin })
        local glow_source = glow_state and "committed" or nil
        if not glow_state then
            glow_state = ctx.glow_picker.native_state_for({ skin = skin })
            if glow_state then glow_source = "native" end
        end
        local resolve_args = {
            backend_id = backend_id,
            exact_instance = true,
            item_type = item_type,
            skin = skin,
            offhand_unit = offhand_unit,
            offhand_armoury_key = offhand_armoury_key,
            glow_state = glow_state,
            glow_source = glow_source,
        }
        local descriptor, reason = COMPOSITE_ICONS.resolve_detailed(resolve_args)
        if descriptor and publish_for_icon ~= false then
            local ready, icon_reason = COMPOSITE_ICONS.icon_ready(
                descriptor, ui_icon_available)
            if not ready then
                descriptor = nil
                reason = icon_reason
            end
        end
        if COMPOSITE_ICONS.claim_diagnostic(reason, resolve_args) then
            mod:info("[cosmetics:650] descriptor %s bid=%s type=%s skin=%s offhand=%s armoury=%s glow=%s held=%s primary=%s shield=%s",
                tostring(reason), tostring(resolve_args.backend_id),
                tostring(resolve_args.item_type), tostring(resolve_args.skin),
                tostring(resolve_args.offhand_unit),
                tostring(resolve_args.offhand_armoury_key),
                tostring(resolve_args.glow_source),
                tostring(descriptor and descriptor.shield_glow
                    and descriptor.shield_glow.variable),
                tostring(descriptor and descriptor.primary_texture),
                tostring(descriptor and descriptor.offhand_texture))
        end
        if publish_for_icon ~= false then COMPOSITE_ICONS.publish(item, descriptor) end
        return descriptor, reason
    end

    local function localized_name(key)
        if type(key) ~= "string" or key == "" then return nil end
        local L = context().get_localize()
        if type(L) ~= "function" then return key end
        local ok, value = pcall(L, key)
        if ok and type(value) == "string" and value ~= ""
                and value ~= key and value ~= "<" .. key .. ">" then
            return value
        end
        return key
    end

    local function presentation_ownership(item_type)
        if mod._independent_dual_item_types
                and mod._independent_dual_item_types[item_type] then return "dual" end
        if context().shield_icon_owner_item_types[item_type] then return "shield" end
        return nil
    end

    local function option_for_record(item, record, exact_skin)
        if type(record) ~= "table" then return nil end
        local ctx = context()
        local ItemMasterList = ctx.get_item_master_list()
        local item_data = item and (item.data or (item.key and ItemMasterList
            and rawget(ItemMasterList, item.key)))
        local item_type = item_data and item_data.item_type
        local pools = mod._ensure_independent_dual_pool
            and mod._ensure_independent_dual_pool(item_type)
            or ctx.offhand_options[item_type]
        local option = ctx.offhand_names.match_option(record,
            pools and pools.left_hand_unit)
        if not option and record.name
                and (record.unit or record.intended_unit or record.la_armoury_key) then
            option = record
        end
        if not option then return nil end
        local external_la = option.la_armoury_key
            and option.cos_authored ~= true
        if external_la then
            local la_mod = ctx.get_mod("Loremasters-Armoury")
            option = mod._la_option_icon_policy.resolve_for_item(option, item_type,
                exact_skin or (item and item.skin), la_mod and la_mod.SKIN_LIST,
                ctx.la_bridge.normalize_weapon_type)
        end
        if not external_la and not option.inventory_icon
                and (option.unit or option.intended_unit) then
            local recovered = ctx.inventory_icon_for_offhand_unit(
                option.unit or option.intended_unit, nil)
            if recovered then
                local copy = {}
                for key, value in pairs(option) do copy[key] = value end
                copy.inventory_icon = recovered
                option = copy
            end
        end
        return option
    end

    local function primary_component_name(item, display_name, ownership, saved_illusion)
        local fallback = localized_name(display_name)
        if ownership ~= "shield" then return fallback end
        local ctx = context()
        local WeaponSkins = ctx.get_weapon_skins()
        local skin_key = saved_illusion or (item and item.skin)
        local skin = skin_key and WeaponSkins and WeaponSkins.skins
            and WeaponSkins.skins[skin_key]
        local data = type(skin) == "table" and (skin.data or skin) or nil
        local primary_unit = data and data.right_hand_unit
        if not primary_unit then return fallback end
        local records = {}
        for key, candidate in pairs(WeaponSkins.skins or {}) do
            local cdata = type(candidate) == "table"
                and (candidate.data or candidate) or nil
            if cdata and cdata.right_hand_unit == primary_unit and cdata.display_name then
                records[#records + 1] = {
                    key = type(key) == "string" and key or candidate.name,
                    primary_unit = primary_unit,
                    name = localized_name(cdata.display_name),
                    is_pair = cdata.left_hand_unit ~= nil,
                }
            end
        end
        return ctx.offhand_names.primary_name_for_unit(primary_unit, records)
            or fallback
    end

    local function publish_presentation_name(primary_name, secondary_name)
        local ctx = context()
        local key, combined = ctx.offhand_names.presentation_key(
            primary_name, secondary_name)
        if not key then return nil end
        mod._cos.presentation_localization[key] = combined
        return key
    end

    local function resolve_presentation(item, base_icon, display_name,
            base_description, ownership, record, saved_illusion)
        local ctx = context()
        local exact_skin = item and item.skin
            or (type(record) == "table"
                and (record.vanilla_skin or record.vanilla_key))
        local option = option_for_record(item, record, exact_skin)
        if not option then return base_icon, display_name, base_description, false end
        local primary = primary_component_name(
            item, display_name, ownership, saved_illusion)
        local descriptor = ctx.item_presentation.resolve({
            base_icon = base_icon,
            primary_name = primary,
            secondary_option = option,
            ownership = ownership,
            local_resource_available = ui_icon_available,
        })
        if not descriptor.changed then
            return base_icon, display_name, base_description, false
        end
        local name_key = publish_presentation_name(
            descriptor.primary_name, descriptor.secondary_name)
        local description_key, description_text =
            ctx.offhand_names.description_presentation_key(
                descriptor.secondary_description)
        if description_key then
            mod._cos.presentation_localization[description_key] = description_text
        end
        return descriptor.icon, name_key or display_name,
            description_key or base_description, true
    end

    owner.ui_icon_available = ui_icon_available
    owner.active_skin = active_skin
    owner.resolve_composed_appearance = resolve_composed_appearance
    owner.presentation_ownership = presentation_ownership
    owner.option_for_record = option_for_record
    owner.resolve_presentation = resolve_presentation

    local UIUtils = deps.ui_utils
    if UIUtils and type(UIUtils.get_ui_information_from_item) == "function" then
        mod:hook(UIUtils, "get_ui_information_from_item", function(func, item)
            local ctx = context()
            local inventory_icon, display_name, description, store_icon = func(item)
            if item and item._cos_presentation_display_name then
                display_name = item._cos_presentation_display_name
            end
            local backend_id = item and (item.backend_id or item.ItemInstanceId)
            if backend_id and ctx.la_instance_policy and ctx.la_persist then
                local la = ctx.get_mod("Loremasters-Armoury")
                local ItemMasterList = ctx.get_item_master_list()
                local item_data = item.data or (item.key and ItemMasterList
                    and rawget(ItemMasterList, item.key))
                local item_type = item_data and item_data.item_type
                local ownership = presentation_ownership(item_type)
                local saved_offhands = ctx.la_persist.get_saved_offhands_for(backend_id)
                local saved_left = saved_offhands and saved_offhands.left_hand_unit
                if ownership == "shield" and type(saved_left) == "table"
                        and not saved_left.armoury_key and not saved_left.inventory_icon
                        and saved_left.unit_path then
                    local recovered_icon = ctx.inventory_icon_for_offhand_unit(
                        saved_left.unit_path, item_data and item_data.template)
                    if recovered_icon then
                        local recovered_left = {}
                        for key, value in pairs(saved_left) do
                            recovered_left[key] = value
                        end
                        recovered_left.inventory_icon = recovered_icon
                        saved_offhands = { left_hand_unit = recovered_left }
                    end
                end
                local saved_illusion = ctx.la_persist.get_saved_illusion(backend_id)
                local icon = ctx.la_icon_provider.resolve(item, saved_illusion,
                    saved_offhands,
                    ctx.la_bridge and ctx.la_bridge.backend_to_armoury,
                    ctx.la_bridge and ctx.la_bridge.backend_to_vanilla,
                    la and la.SKIN_LIST,
                    ownership)
                if icon then inventory_icon = icon end
                ctx.offhand_session_state.migrate_legacy(backend_id)
                local live_hands = ctx.offhand_selection[backend_id]
                local record = live_hands and live_hands.left_hand_unit
                    or (saved_offhands and saved_offhands.left_hand_unit)
                inventory_icon, display_name, description = resolve_presentation(item,
                    inventory_icon, display_name, description, ownership, record,
                    saved_illusion)
                resolve_composed_appearance(item, record)
            end
            return inventory_icon, display_name, description, store_icon
        end)
    end

    owner.install_peer = function(peer_deps)
        assert(type(peer_deps) == "table", "peer presentation dependencies are required")
        assert(type(peer_deps.la_equips_by_peer) == "table",
            "la_equips_by_peer is required")
        assert(type(peer_deps.get_offhand_mesh_by_peer) == "function",
            "get_offhand_mesh_by_peer is required")
        owner.peer_ctx = peer_deps
        if owner.peer_installed then return owner end
        owner.peer_installed = true

        mod._cos.resolve_peer_item_presentation = function(wearer_peer,
                ui_slot_name, item, base_icon, base_display_name, base_description)
            local ctx = context()
            local peer_ctx = owner.peer_ctx
            local item_data = item and item.data
            local item_type = item_data and item_data.item_type
            local ownership = presentation_ownership(item_type)
            if not (wearer_peer and ownership) then return nil end

            local candidate_keys, seen = {}, {}
            local function add(value)
                if type(value) == "string" and value ~= "" and not seen[value] then
                    seen[value] = true
                    candidate_keys[#candidate_keys + 1] = value
                end
            end
            add(ui_slot_name)
            add(item_data and item_data.template)
            add(item_data and item_data.name)
            add(item_data and item_data.key)
            add(item_type)
            add(item and item.name)
            add(item and item.key)

            local record = ctx.item_presentation.find_peer_record(wearer_peer,
                candidate_keys, peer_ctx.la_equips_by_peer,
                peer_ctx.get_offhand_mesh_by_peer())
            if not record then return nil end

            if base_icon == nil or base_display_name == nil
                    or base_description == nil then
                local UIUtils = ctx.ui_utils
                local icon, name, description =
                    UIUtils.get_ui_information_from_item(item)
                base_icon = base_icon or icon
                base_display_name = base_display_name or name
                base_description = base_description or description
            end
            local icon, display_name, description, changed = resolve_presentation(
                item, base_icon, base_display_name, base_description,
                ownership, record, nil)
            if not changed then return nil end
            return {
                icon = icon,
                display_name = display_name,
                description = description,
                ownership = ownership,
                source = "peer_cache",
            }
        end
        return owner
    end

    return owner
end

return Runtime
