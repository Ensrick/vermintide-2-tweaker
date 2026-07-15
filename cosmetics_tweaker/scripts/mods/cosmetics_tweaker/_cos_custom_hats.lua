-- Cosmetics-authored hats that reuse vanilla attachment contracts while
-- carrying their own compiled unit/material resources. Registration is
-- unconditional and deterministic; settings only control availability and
-- rendering, never NetworkLookup membership.

local mod = get_mod("cosmetics_tweaker")
local M = {}

M.ITEM_KEY = "cos_encarmine_hat"
M.VARIANT_KEY = "cos_custom_encarmine_hat"
M.BASE_KEY = "knight_hat_0006"
M.BASE_UNIT = "units/beings/player/empire_soldier_knight/headpiece/es_k_hat_07"
-- v0.9.110's custom package compiled successfully but retained an unresolved
-- runtime dependency. PackageManager fatals are engine-side and bypass pcall,
-- so a persisted equip can otherwise crash again as soon as a preview loads.
-- Keep the candidate path for diagnostics, but fail closed on the proven
-- inventory-package-listed vanilla unit until dependency closure is verified.
M.CANDIDATE_CUSTOM_UNIT = "units/cosmetics_tweaker/encarmine_hat/encarmine_hat"
M.CUSTOM_UNIT = M.BASE_UNIT
M.registered = false

local ITEM_LOCALIZATION = {
    cos_encarmine_hat_name = "Encarmine Helmet",
    cos_encarmine_hat_description =
        "A red-and-gold Foot Knight helm with a black plume, created for Tweaker: Cosmetics.",
}
M.ITEM_LOCALIZATION = ITEM_LOCALIZATION

local function enabled()
    if not mod or type(mod.get) ~= "function" then return true end
    local ok, value = pcall(mod.get, mod, "cos_encarmine_hat_enabled")
    return not ok or value ~= false
end

function M.is_enabled()
    return enabled()
end

function M.resolve_variant(key)
    if key ~= M.VARIANT_KEY then return nil end
    local active = enabled()
    return {
        kind = "custom_unit",
        swap_hand = "hat",
        new_units = { active and M.CUSTOM_UNIT or M.BASE_UNIT },
        is_vanilla_unit = M.CUSTOM_UNIT == M.BASE_UNIT or not active,
        cos_authored = true,
        enabled = active,
    }
end

local function build_entry()
    local original = ItemMasterList and rawget(ItemMasterList, M.BASE_KEY)
    if type(original) ~= "table" then return nil end
    local entry = table.clone(original)
    entry.key = M.ITEM_KEY
    entry.name = M.ITEM_KEY
    entry.display_name = "cos_encarmine_hat_name"
    entry.description = "cos_encarmine_hat_description"
    entry.localized_name = ITEM_LOCALIZATION.cos_encarmine_hat_name
    entry.localized_description = ITEM_LOCALIZATION.cos_encarmine_hat_description
    entry.inventory_icon = "icon_knight_hat_0006_encarmine"
    entry.unit = enabled() and M.CUSTOM_UNIT or M.BASE_UNIT
    entry.rarity = "exotic"
    entry.required_dlc = nil
    entry.can_wield = enabled() and { "es_knight" } or {}
    entry.cos_authored = true
    entry.cos_vanilla_fallback = M.BASE_KEY
    entry.mod_data = {
        backend_id = M.ITEM_KEY,
        ItemInstanceId = M.ITEM_KEY,
        key = M.ITEM_KEY,
        ItemId = M.ITEM_KEY,
        CustomData = { rarity = "exotic" },
        rarity = "exotic",
    }
    return entry
end

function M.sync_toggle()
    local entry = ItemMasterList and rawget(ItemMasterList, M.ITEM_KEY)
    if not entry then return false end
    entry.unit = enabled() and M.CUSTOM_UNIT or M.BASE_UNIT
    entry.can_wield = enabled() and { "es_knight" } or {}
    return true
end

function M.register_all(bridge)
    if M.registered then
        M.sync_toggle()
        return true
    end
    if not (ItemMasterList and NetworkLookup and NetworkLookup.item_names) then return false end
    if not (mod and type(mod.add_mod_items_to_masterlist) == "function"
            and type(mod.add_mod_items_to_local_backend) == "function") then
        return false
    end

    local entry = build_entry()
    if not entry then return false end
    mod:add_mod_items_to_masterlist({ entry })
    mod:add_mod_items_to_local_backend({ entry }, "cosmetics_tweaker")

    if bridge then
        bridge.backend_to_armoury[M.ITEM_KEY] = M.VARIANT_KEY
        bridge.backend_to_vanilla[M.ITEM_KEY] = M.BASE_KEY
        bridge.armoury_to_backend[M.VARIANT_KEY] = M.ITEM_KEY
        -- Never alias the shared vanilla fallback path as a custom clone: that
        -- would make ordinary Laurel Helm instances look like this item.
        if M.CUSTOM_UNIT ~= M.BASE_UNIT then
            bridge.unit_path_to_clones[M.CUSTOM_UNIT] = bridge.unit_path_to_clones[M.CUSTOM_UNIT] or {}
            bridge.unit_path_to_clones[M.CUSTOM_UNIT][#bridge.unit_path_to_clones[M.CUSTOM_UNIT] + 1] = M.ITEM_KEY
        end
        bridge.custom_variants = bridge.custom_variants or {}
        bridge.custom_variants[M.VARIANT_KEY] = true
        -- `registered` means the shared net-safe appearance registry is live.
        -- LA's own one-time registration is tracked independently.
        bridge.registered = true
    end

    M.registered = true
    mod:warning("[cos:encarmine] safe fallback active: %s -> %s (candidate=%s enabled=%s)",
        M.ITEM_KEY, M.BASE_UNIT, M.CANDIDATE_CUSTOM_UNIT, tostring(enabled()))
    return true
end

return M
