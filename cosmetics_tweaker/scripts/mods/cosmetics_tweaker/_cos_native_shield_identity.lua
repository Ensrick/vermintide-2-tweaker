-- Native Sword-and-Shield component admission (#657). Engine-free, read-only.
-- A unit-only committed shield is normalized through an explicit native source
-- row, never a global first-match skin scan, display name, or wire unit path.
local M = { SCHEMA = 1 }
local TARGETS = {
    es_sword_shield = "es_1h_sword_shield",
    es_sword_shield_breton = "es_1h_sword_shield_breton",
}
local SOURCE_TYPES = {
    es_sword_shield = "es_1h_sword_shield",
    es_sword_shield_breton = "es_1h_sword_shield_breton",
    es_deus_01 = "es_deus_01",
}
local KEYS = {
    es_1h_sword_shield = "es_sword_shield",
    es_1h_sword_shield_breton = "es_sword_shield_breton",
}
-- 6.13 native WeaponSkins + ItemMasterList matching_item_key. The red runed
-- GK unit is intentionally absent: blue/purple/glowing aliases share that unit
-- and a legacy unit-only save cannot prove which material identity was chosen.
local SOURCES = {
    es_1h_sword_shield_skin_01 = { "es_sword_shield", "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1" },
    es_1h_sword_shield_skin_02 = { "es_sword_shield", "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02" },
    es_1h_sword_shield_skin_03 = { "es_sword_shield", "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03" },
    es_1h_sword_shield_skin_04 = { "es_sword_shield", "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04" },
    es_1h_sword_shield_skin_05 = { "es_sword_shield", "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05" },
    es_sword_shield_breton_skin_01 = { "es_sword_shield_breton", "units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02" },
    es_sword_shield_breton_skin_02 = { "es_sword_shield_breton", "units/weapons/player/wpn_emp_gk_shield_04/wpn_emp_gk_shield_04" },
    es_sword_shield_breton_skin_03 = { "es_sword_shield_breton", "units/weapons/player/wpn_emp_gk_shield_05/wpn_emp_gk_shield_05" },
    es_sword_shield_breton_skin_04 = { "es_sword_shield_breton", "units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01" },
    es_sword_shield_breton_skin_05 = { "es_sword_shield_breton", "units/weapons/player/wpn_emp_gk_shield_03/wpn_emp_gk_shield_03" },
    es_deus_01_skin_02 = { "es_deus_01", "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02" },
    es_deus_01_skin_03 = { "es_deus_01", "units/weapons/player/wpn_es_deus_shield_03/wpn_es_deus_shield_03" },
}
local function field(row, key)
    return type(row) == "table" and rawget(row, key) or nil
end
local function read(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, value = pcall(fn, ...)
    return ok and value or nil
end
local function nonempty(value)
    return type(value) == "string" and value ~= "" and value or nil
end
function M.supports_type(item_type)
    return KEYS[item_type] ~= nil
end
function M.new(deps)
    deps = deps or {}
    local owner = { schema = M.SCHEMA }
    function owner.admit(item_key, item_type, hand, skin)
        if TARGETS[item_key] ~= item_type or not TARGETS[item_key]
                or hand ~= "left_hand_unit" then return nil, "native_target" end
        local source = SOURCES[skin]
        if not source then return nil, "native_source" end
        local items, skins = read(deps.get_item_master), read(deps.get_weapon_skins)
        local base, donor = field(items, item_key), field(items, source[1])
        local item, skin_row = field(items, skin), field(skins, skin)
        if field(base, "item_type") ~= item_type or field(donor, "item_type") ~= SOURCE_TYPES[source[1]]
                or field(item, "item_type") ~= "weapon_skin"
                or field(item, "matching_item_key") ~= source[1]
                or field(skin_row, hand) ~= source[2]
                or (field(item, hand) and field(item, hand) ~= source[2]) then
            return nil, "native_registry"
        end
        for _, row in ipairs({ base, donor, item }) do
            local dlc = field(row, "required_dlc")
            if dlc and read(deps.dlc_owned, dlc) ~= true then
                return nil, "native_dlc"
            end
        end
        local pool = read(deps.get_pool, item_type, hand)
        local found = false
        for i = 1, 128 do
            local option = field(pool, i)
            if option and not field(option, "la_armoury_key")
                    and (field(option, "unit") or field(option, "intended_unit")) == source[2] then
                local declared = field(option, "source_skin_key") or field(option, "skin_key")
                if not declared or declared == skin then found = true; break end
            end
        end
        if not found then return nil, "native_pool" end
        return { schema = M.SCHEMA, item_key = item_key, item_type = item_type,
            hand = hand, skin_key = skin, source_item_key = source[1], unit = source[2] }, "native_exact"
    end
    function owner.committed(backend_id, item_type, hand)
        if not KEYS[item_type] or hand ~= "left_hand_unit" or backend_id == nil then
            return nil, "native_target"
        end
        if type(deps.get_saved) ~= "function" then return nil, "native_saved_unreadable" end
        local ok, hands = pcall(deps.get_saved, backend_id)
        if not ok or (hands ~= nil and type(hands) ~= "table") then
            return nil, "native_saved_unreadable"
        end
        local saved = field(hands, hand)
        if saved == nil then return nil, "follow_main" end
        if type(saved) ~= "table" or field(saved, "la_armoury_key") then
            return nil, "native_saved"
        end
        local unit, skin = nonempty(field(saved, "unit_path")), nonempty(field(saved, "vanilla_key"))
        if not skin then
            if not unit then return nil, "native_saved" end
            for key, source in pairs(SOURCES) do
                if source[2] == unit then
                    if skin then return nil, "native_ambiguous" end
                    skin = key
                end
            end
        end
        if not skin then return nil, "native_source" end
        local proof, reason = owner.admit(KEYS[item_type], item_type, hand, skin)
        if not proof then return nil, reason end
        if unit and unit ~= proof.unit then return nil, "native_saved_unit" end
        return skin, "committed"
    end
    return owner
end
return M
