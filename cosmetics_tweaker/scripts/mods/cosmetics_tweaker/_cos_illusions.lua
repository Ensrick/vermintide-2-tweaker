-- _cos_illusions.lua -- custom weapon-illusion + LA shield skin injection.
--
-- Owns the runtime injection of new selectable weapon skins into ItemMasterList,
-- WeaponSkins.skins, skin_combinations and NetworkLookup.weapon_skins: the ct_*
-- cross-character shield/weapon illusions (_custom_illusions) and the LA shield
-- skin specs (_la_shield_skin_specs; its registration call is intentionally
-- disabled, kept for reference). Also owns the get_unlocked_weapon_skins unlock
-- hook and the _G.Localize display-name hook for these keys. Split out of the god
-- file in v0.9.77-dev Phase 1; no behavior change.
--
-- Owned by: cosmetics_tweaker.lua entry point. Consumed via: mod:dofile.
-- Shared state: registers keys into mod._cos.custom_skin_keys (the wire-safety
-- null-and-restore senders and the regression suite read the same table); reads
-- mod._cos.skin_requires_unowned_dlc (DLC gate) and mod._cos.LA_BRIDGE
-- (Localize fallback).

local mod = get_mod("cosmetics_tweaker")
local COS = mod._cos
local LA_BRIDGE = COS.LA_BRIDGE
local _skin_requires_unowned_dlc = COS.skin_requires_unowned_dlc

-- ============================================================
-- Custom Weapon Illusions (shield/weapon model combos)
-- ============================================================
-- Each entry creates a new selectable illusion for an existing weapon,
-- injected into ItemMasterList, WeaponSkins.skins, and skin_combinations.

local _custom_illusions = {
    {
        skin_key         = "ct_es_mace_gk_shield_01",
        matching_weapon  = "es_mace_shield",
        display_name     = "Mace & Bretonnian Shield",
        rarity           = "exotic",
        right_hand_unit  = "units/weapons/player/wpn_emp_mace_02_t2/wpn_emp_mace_02_t2",
        left_hand_unit   = "units/weapons/player/wpn_emp_gk_shield_03/wpn_emp_gk_shield_03",
        display_unit     = "units/weapons/weapon_display/display_shield_hammer",
        template         = "one_handed_hammer_shield_template_1",
        can_wield        = { "es_mercenary", "es_knight", "es_huntsman", "es_questingknight" },
    },

    -- Spear & Shield spear models on Tuskgor Spear (right hand only, no shield)
    {
        skin_key         = "ct_es_heavy_spear_deus_01",
        matching_weapon  = "es_2h_heavy_spear",
        display_name     = "Spear & Shield Spear",
        rarity           = "exotic",
        right_hand_unit  = "units/weapons/player/wpn_es_deus_spear_01/wpn_es_deus_spear_01",
        display_unit     = "units/weapons/weapon_display/display_2h_heavy_spears",
        template         = "two_handed_heavy_spears_template",
        can_wield        = { "es_mercenary", "es_knight", "es_huntsman", "es_questingknight" },
    },
    {
        skin_key         = "ct_es_heavy_spear_deus_02",
        matching_weapon  = "es_2h_heavy_spear",
        display_name     = "Spear & Shield Spear (Ornate)",
        rarity           = "exotic",
        right_hand_unit  = "units/weapons/player/wpn_es_deus_spear_02/wpn_es_deus_spear_02",
        display_unit     = "units/weapons/weapon_display/display_2h_heavy_spears",
        template         = "two_handed_heavy_spears_template",
        can_wield        = { "es_mercenary", "es_knight", "es_huntsman", "es_questingknight" },
    },
    {
        skin_key         = "ct_es_heavy_spear_deus_03",
        matching_weapon  = "es_2h_heavy_spear",
        display_name     = "Spear & Shield Spear (Plumed)",
        rarity           = "exotic",
        right_hand_unit  = "units/weapons/player/wpn_es_deus_spear_03/wpn_es_deus_spear_03",
        display_unit     = "units/weapons/weapon_display/display_2h_heavy_spears",
        template         = "two_handed_heavy_spears_template",
        can_wield        = { "es_mercenary", "es_knight", "es_huntsman", "es_questingknight" },
    },
}

local _custom_skin_keys = COS.custom_skin_keys

local function _register_custom_illusions()
    if not ItemMasterList or not WeaponSkins then return end

    for _, illusion in ipairs(_custom_illusions) do
        local skin_key = illusion.skin_key
        if _custom_skin_keys[skin_key] then goto continue end

        ItemMasterList[skin_key] = {
            item_type         = "weapon_skin",
            slot_type         = "weapon_skin",
            matching_item_key = illusion.matching_weapon,
            rarity            = illusion.rarity,
            display_name      = skin_key .. "_name",
            description       = skin_key .. "_description",
            display_unit      = illusion.display_unit,
            hud_icon          = "weapon_generic_icon_staff_3",
            inventory_icon    = "icon_wpn_empire_shield_01_t1_mace",
            information_text  = "information_weapon_skin",
            right_hand_unit   = illusion.right_hand_unit,
            left_hand_unit    = illusion.left_hand_unit,
            template          = illusion.template,
            can_wield         = illusion.can_wield,
        }

        WeaponSkins.skins[skin_key] = {
            description     = skin_key .. "_description",
            display_name    = skin_key .. "_name",
            display_unit    = illusion.display_unit,
            hud_icon        = "weapon_generic_icon_staff_3",
            inventory_icon  = "icon_wpn_empire_shield_01_t1_mace",
            rarity          = illusion.rarity,
            right_hand_unit = illusion.right_hand_unit,
            left_hand_unit  = illusion.left_hand_unit,
            template        = illusion.template,
        }

        local weapon_data = rawget(ItemMasterList, illusion.matching_weapon)
        if weapon_data and weapon_data.skin_combination_table then
            local combos = WeaponSkins.skin_combinations[weapon_data.skin_combination_table]
            if combos then
                local tier = combos[illusion.rarity] or combos.exotic or combos.common
                if tier then
                    tier[#tier + 1] = skin_key
                end
            end
        end

        -- CLARIFY: rawget is required because NetworkLookup.weapon_skins has
        -- a __index metatable that errors on missing keys (per v0.6.23 fix).
        -- Same class as ItemMasterList. Do NOT change to plain bracket lookup.
        if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, skin_key) then
            local tbl = NetworkLookup.weapon_skins
            tbl[#tbl + 1] = skin_key
            tbl[skin_key] = #tbl
        end

        _custom_skin_keys[skin_key] = true
        mod:info("Registered custom illusion: %s -> %s", skin_key, illusion.matching_weapon)
        ::continue::
    end
end

_register_custom_illusions()

-- ============================================================
-- LA Shield Skin Injection (Phase 1)
-- ============================================================
-- LA shields registered as first-class VT2 skins per (LA shield × weapon
-- type) pair. Each combo becomes a real entry in ItemMasterList,
-- WeaponSkins.skins, and the appropriate skin_combinations table — same
-- pipeline `_register_custom_illusions` already uses for the existing
-- `ct_*` cross-character illusions.
--
-- Why this replaces the older runtime-override approach:
--   1. PER-WEAPON-INSTANCE. Vanilla's `craftingApplySkin2` writes
--      `item.skin = skin_key` onto the specific backend item. Selection
--      no longer leaks across weapons that share `item_type` (e.g.
--      modded CWV imperial sword+shield no longer renders Reiland just
--      because the user picked Reiland on a different Bret weapon).
--   2. STANDARD APPLY UI. Skins appear in the row-1 illusion grid; user
--      picks them like any other illusion. No separate row-2 widget,
--      no parallel "_offhand_selection" state machine.
--   3. CUSTOMIZATION PREVIEW USES VANILLA SPAWN PATH. Vanilla apply →
--      previewer respawn with the skin's `left_hand_unit` and
--      `right_hand_unit` — the same code path that successfully renders
--      every other custom illusion. Our v0.8.12 short-circuit handles
--      LA-bundled paths in the load_package gate.
--
-- Each spec needs: skin_key (must be unique), matching_weapon (a vanilla
-- weapon item_type), left_hand_unit (LA's mesh path), display_name_key
-- (looked up via _custom_loc by the Localize hook). right_hand_unit,
-- display_unit, template, and can_wield are inherited from the vanilla
-- weapon's default skin so the right side of the weapon is preserved.

local _la_shield_skin_specs = {
    -- Phase 1 PROOF: Reiland (Empire shield 01 mesh) on the Bret
    -- longsword+shield. Verify this displays correctly across all four
    -- spawn paths (in-game body, inventory mannequin, customization
    -- preview, illusion browser) before extending to all 4 weapon types
    -- and the rest of the LA shield catalogue.
    {
        skin_key         = "la_kruber_empire_shield_basic1_breton",
        matching_weapon  = "es_1h_sword_shield_breton",
        left_hand_unit   = "units/empire_shield/Kruber_Empire_shield01_mesh",
        display_name     = "Empire Shield 01 (LA)",
        rarity           = "exotic",
    },
}

local function _get_weapon_default_skin(weapon_key)
    if not WeaponSkins or not WeaponSkins.default_skins then return nil end
    local default_skin_key = WeaponSkins.default_skins[weapon_key]
    if not default_skin_key then return nil end
    return WeaponSkins.skins and WeaponSkins.skins[default_skin_key] or nil
end

local function _register_la_shield_skin(spec)
    if not ItemMasterList or not WeaponSkins then return end
    local skin_key = spec.skin_key
    if _custom_skin_keys[skin_key] then return end

    local weapon_data = rawget(ItemMasterList, spec.matching_weapon)
    if not weapon_data then
        mod:info("[LA skin] missing weapon %s; cannot register %s",
            spec.matching_weapon, skin_key)
        return
    end

    -- Inherit everything from the weapon's default skin EXCEPT left_hand_unit
    -- (LA's mesh) so the weapon's right side is unchanged.
    local default_skin = _get_weapon_default_skin(spec.matching_weapon)
    local right_hand_unit = (default_skin and default_skin.right_hand_unit)
                            or weapon_data.right_hand_unit
    local display_unit = (default_skin and default_skin.display_unit)
                         or weapon_data.display_unit
    local template = (default_skin and default_skin.template)
                     or weapon_data.template
    local can_wield = weapon_data.can_wield

    local rarity = spec.rarity or "exotic"
    local description_key = skin_key .. "_description"

    ItemMasterList[skin_key] = {
        item_type         = "weapon_skin",
        slot_type         = "weapon_skin",
        matching_item_key = spec.matching_weapon,
        rarity            = rarity,
        display_name      = skin_key .. "_name",
        description       = description_key,
        display_unit      = display_unit,
        hud_icon          = "weapon_generic_icon_staff_3",
        inventory_icon    = spec.inventory_icon or "icon_wpn_empire_shield_01_t1_mace",
        information_text  = "information_weapon_skin",
        right_hand_unit   = right_hand_unit,
        left_hand_unit    = spec.left_hand_unit,
        template          = template,
        can_wield         = can_wield,
    }

    WeaponSkins.skins[skin_key] = {
        description     = description_key,
        display_name    = skin_key .. "_name",
        display_unit    = display_unit,
        hud_icon        = "weapon_generic_icon_staff_3",
        inventory_icon  = spec.inventory_icon or "icon_wpn_empire_shield_01_t1_mace",
        rarity          = rarity,
        right_hand_unit = right_hand_unit,
        left_hand_unit  = spec.left_hand_unit,
        template        = template,
    }

    if weapon_data.skin_combination_table then
        local combos = WeaponSkins.skin_combinations[weapon_data.skin_combination_table]
        if combos then
            local tier = combos[rarity] or combos.exotic or combos.common
            if tier then
                tier[#tier + 1] = skin_key
            end
        end
    end

    if NetworkLookup and NetworkLookup.weapon_skins
        and not rawget(NetworkLookup.weapon_skins, skin_key)
    then
        local tbl = NetworkLookup.weapon_skins
        tbl[#tbl + 1] = skin_key
        tbl[skin_key] = #tbl
    end

    _custom_skin_keys[skin_key] = true
    mod:info("[LA skin] registered %s for %s -> mesh=%s right=%s",
        skin_key, spec.matching_weapon, spec.left_hand_unit, tostring(right_hand_unit))
end

local function _register_all_la_shield_skins()
    for _, spec in ipairs(_la_shield_skin_specs) do
        _register_la_shield_skin(spec)
    end
end

-- v0.8.31 REVERT: skin injection put LA shields in the row-1 illusion
-- grid where applying them swaps the WHOLE weapon visual (left+right
-- bundled). User wants row-2 offhand picker behavior — shield
-- independent of main weapon. Skin injection collapses that distinction.
-- The registration code stays here for future reference / a different
-- design but is not invoked. Row-2 picker (`_merge_la_offhand_options`)
-- is restored as the LA surface.
-- _register_all_la_shield_skins()

mod:hook_safe("BackendInterfaceCraftingPlayfab", "get_unlocked_weapon_skins", function(self)
    local mirror = self._backend_mirror
    if not mirror or not mirror._unlocked_weapon_skins then return end
    for skin_key, _ in pairs(_custom_skin_keys) do
        if not _skin_requires_unowned_dlc(skin_key) then -- DLC gate
            mirror._unlocked_weapon_skins[skin_key] = true
        end
    end
    if mod:get("unlock_all_illusions") and script_data["eac-untrusted"] and WeaponSkins then
        for skin_key, _ in pairs(WeaponSkins.skins) do
            if not _skin_requires_unowned_dlc(skin_key) then
                mirror._unlocked_weapon_skins[skin_key] = true
            end
        end
    end
end)

local _custom_loc = {}
-- Item UI calls the game's global Localize(), not VMF's per-mod localizer.
-- Fold custom-hat strings into this module's existing single Localize owner;
-- a second hook would create order-dependent localization and fails lint.
for key, value in pairs(COS.encarmine_item_localization or {}) do
    _custom_loc[key] = value
end
for key, value in pairs(COS.gk_set_item_localization or {}) do
    _custom_loc[key] = value
end
for _, spec in ipairs(_la_shield_skin_specs) do
    _custom_loc[spec.skin_key .. "_name"] = spec.display_name
end
for _, illusion in ipairs(_custom_illusions) do
    _custom_loc[illusion.skin_key .. "_name"] = illusion.display_name
    -- Don't shadow the `_description` entries written in
    -- cosmetics_tweaker_localization.lua. Letting that key fall through
    -- to the vanilla localizer means tooltips show the descriptive text
    -- (e.g. "An Empire mace paired with a Bretonnian shield.") rather
    -- than the title repeated.
end

mod:hook(_G, "Localize", function(func, key, ...)
    -- CLARIFY: hook order matters — _custom_loc takes priority over
    -- LA_BRIDGE.localization, which in turn precedes the vanilla
    -- localizer. If a key collides between custom illusion and LA bridge,
    -- the illusion wins. Today there's no overlap (ct_* vs *_LA_*).
    local custom = _custom_loc[key]
    if custom then return custom end
    local la_loc = LA_BRIDGE.localization[key]
    if la_loc then return la_loc end
    return func(key, ...)
end)

-- Shared with the entry's _force_load_all_offhand_packages (offhand preload),
-- which walks these to preload each illusion's hand-unit packages on every peer.
mod._cos.custom_illusions = _custom_illusions
