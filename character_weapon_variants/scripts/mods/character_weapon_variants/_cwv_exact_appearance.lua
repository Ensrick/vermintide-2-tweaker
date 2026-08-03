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

M.SPAWN_ADAPTERS = {
    inventory_mannequin = "hand_flags",
    customization_preview = "base_identity",
    athanor_preview = "base_identity",
}

local function nonempty(value)
    return type(value) == "string" and value ~= "" and value or nil
end

-- #237/#419: spawn-target 3P resolution honors the injected residency resolver
-- STRICTLY. nil means DEGRADE: the entry keeps the recipe's authored base unit
-- -- never the historical blind `base .. "_3p"` concatenation, which collapsed
-- every resolver decline (sentinel, non-vanilla prefix, non-resident target)
-- into an ungated World.spawn_unit target (the #403/#474 crash class).
-- Match-key comparisons use concat_3p instead: they name what vanilla ALREADY
-- authored into the recipe and must not shrink when a resolver declines the
-- spawn target (a nil match key would break skin-over-variant idempotency).
local function concat_3p(base)
    return base and (base .. "_3p") or nil
end

local function resolved_3p(base, resolve_3p)
    if not base or type(resolve_3p) ~= "function" then return nil end
    return resolve_3p(base)
end

-- #237/#419 preview-time residency gate (pure decision shape; production wires
-- it as _om._preview_override_3p in _cwv_husk_path.lua). The husk resolver
-- (_om._resident_override_3p, issue 418) demands cwv's HUSK_OVERRIDE_REF
-- residency, which only the boot force-load pass and the husk leases establish
-- -- at solo keep preview time it is silent for skin/custom targets, so a
-- second, preview-safe floor decides:
--   1. the husk resolver's answer is final when it speaks (co-op unchanged);
--   2. the invisible-weapon sentinel always degrades to the base mesh;
--   3. only vanilla player meshes and the mod's own bundled `units/cwv_`
--      namespace are eligible at all (any other prefix degrades);
--   4. the injected `spawnable` predicate (production: _om._husk_unit_spawnable,
--      the #478 crash floor incl. the #474 donor-material gate for the Old
--      Musket's MeshObject-AV class) must positively confirm the spawn.
-- Application.can_get inside the production floor is a spawn-SAFETY check only
-- (bundle stubs may still render invisible); it is never a loader gate.
M.VANILLA_PLAYER_PREFIX = "units/weapons/player/"
M.MOD_BUNDLE_PREFIX = "units/cwv_"
M.INVISIBLE_SENTINEL = "wpn_invisible_weapon"

function M.resolve_preview_3p(base, husk_resolver, spawnable)
    if type(base) ~= "string" or base == "" then return nil end
    if type(husk_resolver) == "function" then
        local resolved = husk_resolver(base)
        if resolved ~= nil then return resolved end
    end
    if base:find(M.INVISIBLE_SENTINEL, 1, true) then return nil end
    if base:find(M.VANILLA_PLAYER_PREFIX, 1, true) ~= 1
            and base:find(M.MOD_BUNDLE_PREFIX, 1, true) ~= 1 then
        return nil
    end
    if type(spawnable) ~= "function" or spawnable(base) ~= true then return nil end
    return base .. "_3p"
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
            local want = resolved_3p(base, resolve_3p)
            local default_base = entry.right_hand and fallback and fallback.right_hand_unit
                or (entry.left_hand and fallback and fallback.left_hand_unit)
            local default_3p = concat_3p(default_base)
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

local function unit_from(row, field)
    return type(row) == "table" and nonempty(row[field]) or nil
end

local function descriptor_fingerprint(descriptor)
    local identity = table.concat({
        descriptor.provider or "-",
        descriptor.variant_key or "-",
        descriptor.base_item_key or "-",
        descriptor.skin or "-",
        descriptor.right_hand_unit or "-",
        descriptor.left_hand_unit or "-",
        descriptor.no_ammo_unit and "no-ammo" or "ammo",
    }, "|")
    -- VMF mod messages share Stingray's small string envelope. Never put the
    -- raw unit-path tuple on the wire: two independent bounded arithmetic
    -- hashes keep the correlation token fixed at 19 bytes under Lua 5.1
    -- without bit libraries. This is drift detection, not authentication.
    local h1, h2 = 5381, 52711
    for i = 1, #identity do
        local byte = identity:byte(i)
        h1 = (h1 * 65599 + byte) % 2147483647
        h2 = (h2 * 131071 + byte) % 2147483629
    end
    return string.format("a1:%08x%08x", h1, h2)
end

-- One immutable-by-convention unit descriptor for both preview spawn APIs.
-- The caller supplies the strongest identity it actually owns plus the
-- canonical variant/base rows.  Surface adapters may choose how a spawn row
-- identifies its hand, but they may not resolve skin or variant identity again.
function M.resolve_spawn_descriptor(args)
    args = args or {}
    local variant = args.variant
    if type(variant) ~= "table" then return nil, "variant_missing" end

    local explicit_skin = nonempty(args.explicit_skin)
    local stored_skin = nonempty(args.stored_skin)
    local requested_skin = explicit_skin or stored_skin
    if not requested_skin and nonempty(args.backend_id)
            and type(args.skin_from_backend) == "function" then
        local ok, value = pcall(args.skin_from_backend, args.backend_id)
        if ok then requested_skin = nonempty(value) end
    end
    local exact = M.resolve({
        explicit_skin = explicit_skin,
        stored_skin = requested_skin,
        weapon_skins = args.weapon_skins,
    })
    if requested_skin and not exact then
        return nil, "skin_unresolved"
    end

    local descriptor = {
        provider = nonempty(args.provider) or "cwv",
        instance_id = nonempty(args.instance_id),
        variant_key = nonempty(variant.item_key),
        base_item_key = nonempty(args.base_item_key)
            or nonempty(variant.base_weapon),
        fallback_item_key = nonempty(args.fallback_item_key)
            or nonempty(variant.base_weapon),
        skin = exact and exact.skin or nil,
        source = exact and "skin" or "variant",
        right_hand_unit = exact and exact.right_hand_unit
            or unit_from(variant, "right_hand_unit"),
        left_hand_unit = exact and exact.left_hand_unit
            or unit_from(variant, "left_hand_unit"),
        variant_right_hand_unit = unit_from(variant, "right_hand_unit"),
        variant_left_hand_unit = unit_from(variant, "left_hand_unit"),
        base_right_hand_unit = unit_from(args.base, "right_hand_unit"),
        base_left_hand_unit = unit_from(args.base, "left_hand_unit"),
        -- Some variants intentionally keep the base weapon's ammo mechanics
        -- while replacing its authored ammo mesh.  This is appearance state,
        -- not ammo-count state, so it belongs in the same immutable descriptor
        -- as the hand-unit paths and must participate in its fingerprint.
        no_ammo_unit = variant.no_ammo_unit == true,
    }
    if not descriptor.right_hand_unit and not descriptor.left_hand_unit then
        return nil, "units_missing"
    end
    descriptor.fingerprint = descriptor_fingerprint(descriptor)
    return descriptor
end

-- Apply a previously resolved descriptor to one of the two engine recipe
-- shapes. `hand_flags` is MenuWorldPreviewer's recipe; `base_identity` is the
-- LootItemUnitPreviewer recipe after it rebound item_data to the vanilla base.
function M.apply_spawn_descriptor(descriptor, spawn_data, resolve_3p, adapter)
    if type(descriptor) ~= "table" or type(spawn_data) ~= "table" then return 0 end
    if adapter ~= "hand_flags" and adapter ~= "base_identity" then return 0 end

    local changed = 0
    for index = 1, #spawn_data do
        local entry = spawn_data[index]
        -- #279: vanilla stamps `is_ammo_unit = item_units.ammo_unit ~= nil`
        -- onto the LEFT/RIGHT WEAPON rows themselves
        -- (world_hero_previewer.lua:707/731) -- the flag records ammo-unit
        -- INHERITANCE from the base item (backend_utils.lua:147-148), NOT a
        -- dedicated ammo row. A no-ammo descriptor therefore CLEARS the
        -- inherited ammo identity and lets the row fall through to the exact
        -- hand-unit rewrite below; deleting flagged rows would delete the
        -- weapon row itself and vanish the weapon from the preview.
        if type(entry) == "table" and entry.is_ammo_unit and descriptor.no_ammo_unit then
            entry.is_ammo_unit = nil
            changed = changed + 1
        end
        if type(entry) == "table" and not entry.is_ammo_unit then
            local hand
            if adapter == "hand_flags" then
                hand = entry.right_hand and "right" or (entry.left_hand and "left")
            else
                local name = entry.unit_name
                -- Match the recipe's authored identity directly. Residency is
                -- a gate for the TARGET only; the vanilla base may be resident
                -- under another package ref and must still be recognized.
                local base_right = descriptor.base_right_hand_unit
                    and (descriptor.base_right_hand_unit .. "_3p")
                local base_left = descriptor.base_left_hand_unit
                    and (descriptor.base_left_hand_unit .. "_3p")
                local variant_right = descriptor.source == "skin"
                    and descriptor.variant_right_hand_unit
                    and (descriptor.variant_right_hand_unit .. "_3p")
                local variant_left = descriptor.source == "skin"
                    and descriptor.variant_left_hand_unit
                    and (descriptor.variant_left_hand_unit .. "_3p")
                if entry.right_hand then
                    hand = "right"
                elseif entry.left_hand then
                    hand = "left"
                elseif (base_right and name == base_right) or (variant_right and name == variant_right) then
                    hand = "right"
                elseif (base_left and name == base_left) or (variant_left and name == variant_left) then
                    hand = "left"
                end
            end

            local base = hand and descriptor[hand .. "_hand_unit"]
            local want = resolved_3p(base, resolve_3p)
            local may_replace = true
            if hand and descriptor.source == "skin" then
                local variant_base = descriptor["variant_" .. hand .. "_hand_unit"]
                local variant_3p = concat_3p(variant_base)
                may_replace = entry.unit_name == nil or entry.unit_name == want
                    or (variant_3p and entry.unit_name == variant_3p)
            end
            if want and may_replace and entry.unit_name ~= want then
                entry.unit_name = want
                changed = changed + 1
            end
        end
    end
    return changed
end

return M
