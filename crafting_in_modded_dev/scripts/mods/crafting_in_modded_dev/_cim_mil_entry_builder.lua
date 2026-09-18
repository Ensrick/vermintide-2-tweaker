-- _cim_mil_entry_builder.lua -- legacy MoreItemsLibrary entry builder.
--
-- Builds the MIL `add_mod_items_to_local_backend` entry for a saved craft
-- flagged `via_mirror = false` (saved crafts from the former console path;
-- all new crafts go through the mirror transaction). Extracted
-- verbatim from the entry's `_forge_create_item` (decomposition ceiling).
--
-- Owned by: crafting_in_modded_dev.lua entry point. Consumed via: mod:dofile.
-- Routes the issue 682/628 record gate: every rejection carries a classified
-- reason (the prior `contract and contract.normalize_record(...)` and/or
-- collapse truncated the multi-return, so rejections logged `reason=nil`).

local mod = get_mod("cim_dev")

return function(weapon_data, backend_id)
    if not ItemMasterList then return nil end
    local item_key = weapon_data.item_key
    local master = rawget(ItemMasterList, item_key)
    if not master then
        mod:echo("Forge: unknown weapon key '" .. tostring(item_key) .. "'")
        return nil
    end

    -- Surface `mirror_restore`: this MIL path serves legacy `via_mirror=false`
    -- saves.
    local contract = mod._cim_synthetic_item_contract
    local normalized, normalize_err = contract.gate_record("mirror_restore",
        backend_id, weapon_data, master)
    if not normalized then
        printf("[cim:628] rejected MIL injection bid=%s key=%s reason=%s",
            tostring(backend_id), tostring(item_key), tostring(normalize_err))
        return nil
    end
    weapon_data = normalized

    local props = weapon_data.properties or {}
    local trait = weapon_data.trait
    local traits_array = weapon_data.traits
    local skin = weapon_data.skin
    local power_level = weapon_data.power_level or 300

    local custom_props = "{"
    for k, v in pairs(props) do
        custom_props = custom_props .. '"' .. k .. '":' .. tostring(v) .. ','
    end
    custom_props = custom_props .. "}"

    local traits_table = {}
    if traits_array then
        for i, t in ipairs(traits_array) do traits_table[i] = t end
    elseif trait then
        traits_table[1] = trait
    end

    local custom_traits = "["
    for i, t in ipairs(traits_table) do
        if i > 1 then custom_traits = custom_traits .. "," end
        custom_traits = custom_traits .. '"' .. t .. '"'
    end
    custom_traits = custom_traits .. "]"

    local rarity = weapon_data.rarity or "exotic"

    local entry = table.clone(master, true)
    entry.cim_acquisition_key = item_key
    entry.mod_data = {
        backend_id = backend_id,
        ItemInstanceId = backend_id,
        cim_acquisition_key = item_key,
        cwv_key = weapon_data.provider == "cwv" and item_key or nil,
        CustomData = {
            traits = custom_traits,
            power_level = tostring(power_level),
            properties = custom_props,
            rarity = rarity,
            cim_acquisition_key = item_key,
            cim_provider = weapon_data.provider,
            cwv_key = weapon_data.provider == "cwv" and item_key or nil,
        },
        rarity = rarity,
        traits = traits_table,
        power_level = power_level,
        properties = table.clone(props, true),
    }
    if skin then
        entry.mod_data.CustomData.skin = skin
        entry.mod_data.skin = skin
        if WeaponSkins and WeaponSkins.skins and WeaponSkins.skins[skin] then
            entry.mod_data.inventory_icon = WeaponSkins.skins[skin].inventory_icon
        end
    end
    entry.rarity = rarity

    local registered, register_reason = contract.register_legacy_mil_entry(
        weapon_data, master, entry)
    if not registered then
        printf("[cim:1141] rejected MIL issuance bid=%s key=%s reason=%s",
            tostring(backend_id), tostring(item_key), tostring(register_reason))
        return nil
    end

    return entry
end
