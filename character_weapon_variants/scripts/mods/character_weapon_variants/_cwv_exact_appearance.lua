-- Canonical exact-illusion appearance resolver for every CWV render surface.
--
-- The engine has several adapters (live equipment, remote husks, inventory
-- mannequin, illusion browser, score-screen HeroPreviewer), but an exact skin
-- has only one model answer: the per-hand paths authored in WeaponSkins.skins.
-- Keep identity resolution and recipe application here so a new surface cannot
-- grow a family-specific reconstruction rule.
local M = {}

M.SURFACES = {
    owner_3p = "item_units",
    remote_husk = "item_units",
    inventory_mannequin = "spawn_data",
    customization_preview = "spawn_data",
    score_screen = "spawn_data",
}

local function nonempty(value)
    return type(value) == "string" and value ~= "" and value or nil
end

function M.resolve(args)
    args = args or {}
    local skin = nonempty(args.explicit_skin) or nonempty(args.stored_skin)
    if not skin and nonempty(args.backend_id) and type(args.skin_from_backend) == "function" then
        local ok, value = pcall(args.skin_from_backend, args.backend_id)
        if ok then skin = nonempty(value) end
    end
    if not skin then return nil end

    local skins = args.weapon_skins
    local row = type(skins) == "table" and skins[skin] or nil
    if type(row) ~= "table" then return nil end
    local right = nonempty(row.right_hand_unit)
    local left = nonempty(row.left_hand_unit)
    if not right and not left then return nil end

    return { skin = skin, right_hand_unit = right, left_hand_unit = left }
end

function M.apply_item_units(appearance, result, preserve_existing)
    if type(appearance) ~= "table" or type(result) ~= "table" then return 0 end
    local changed = 0
    for _, hand in ipairs({ "right_hand_unit", "left_hand_unit" }) do
        local want = appearance[hand]
        if want and result[hand] ~= want
                and (not preserve_existing or result[hand] == nil or result[hand] == "") then
            result[hand] = want
            changed = changed + 1
        end
    end
    if appearance.skin then result.skin = appearance.skin end
    return changed
end

function M.apply_spawn_data(appearance, spawn_data, resolve_3p, fallback)
    if type(appearance) ~= "table" or type(spawn_data) ~= "table" then return 0 end
    local changed = 0
    for _, entry in ipairs(spawn_data) do
        if type(entry) == "table" and not entry.is_ammo_unit then
            local base = entry.right_hand and appearance.right_hand_unit
                or (entry.left_hand and appearance.left_hand_unit)
            local want = base and (resolve_3p and resolve_3p(base) or (base .. "_3p"))
            local default_base = entry.right_hand and fallback and fallback.right_hand_unit
                or (entry.left_hand and fallback and fallback.left_hand_unit)
            local default_3p = default_base
                and (resolve_3p and resolve_3p(default_base) or (default_base .. "_3p"))
            -- A different non-default hand may be Cosmetics' exact per-instance
            -- offhand. CWV owns the primary skin but must compose, not clobber.
            local may_replace = not fallback or entry.unit_name == nil
                or entry.unit_name == want or entry.unit_name == default_3p
            if want and may_replace and entry.unit_name ~= want then
                entry.unit_name = want
                changed = changed + 1
            end
        end
    end
    return changed
end

return M
