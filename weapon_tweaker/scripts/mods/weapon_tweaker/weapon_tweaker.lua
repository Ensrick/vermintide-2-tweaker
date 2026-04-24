local mod = get_mod("wt")
local weapon_backend = mod:dofile("scripts/mods/weapon_tweaker/weapon_tweaker_backend")

local MOD_VERSION = "0.3.0-dev"
mod:info("Weapon Tweaker v%s loaded", MOD_VERSION)
mod:echo("Weapon Tweaker v" .. MOD_VERSION)

local weapon_unlock_map = {
    -- Kruber (es_1h_sword, es_1h_mace, dr_1h_axe are native)
    es_mercenary      = { "dr_1h_axe", "es_sword_shield_breton", "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer", "dr_shield_hammer" },
    es_huntsman       = { "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer", "dr_shield_hammer" },
    es_knight         = { "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer", "es_2h_heavy_spear", "dr_shield_hammer" },
    es_questingknight = { "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer", "es_2h_heavy_spear", "we_1h_spears_shield", "es_halberd", "dr_shield_hammer" },
    -- Bardin (dr_1h_hammer, dr_1h_axe are native)
    dr_ranger         = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "es_mace_shield" },
    dr_ironbreaker    = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "es_mace_shield" },
    dr_slayer         = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "es_mace_shield" },
    dr_engineer       = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "wh_1h_axe", "we_1h_sword", "es_mace_shield" },
    -- Kerillian (we_1h_sword is native)
    we_waywatcher     = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "we_1h_spears_shield", "we_crossbow_repeater" },
    we_maidenguard    = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "we_crossbow_repeater" },
    we_shade          = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "we_1h_spears_shield" },
    we_thornsister    = { "es_1h_sword", "es_1h_mace", "bw_sword", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "dr_1h_hammer", "we_1h_spears_shield", "we_crossbow_repeater" },
    -- Saltzpyre (wh_1h_falchion, wh_1h_axe are native)
    wh_captain        = { "es_1h_sword", "es_1h_mace", "bw_sword", "dr_1h_axe", "we_1h_sword", "dr_1h_hammer" },
    wh_bountyhunter   = { "es_1h_sword", "es_1h_mace", "bw_sword", "dr_1h_axe", "we_1h_sword", "dr_1h_hammer" },
    wh_zealot         = { "es_1h_sword", "es_1h_mace", "bw_sword", "dr_1h_axe", "we_1h_sword", "dr_1h_hammer" },
    wh_priest         = { "es_1h_sword", "es_1h_mace", "bw_sword", "dr_1h_axe", "we_1h_sword", "dr_1h_hammer" },
    -- Sienna (bw_sword is native)
    bw_scholar        = { "es_1h_sword", "es_1h_mace", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer" },
    bw_adept          = { "es_1h_sword", "es_1h_mace", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer" },
    bw_unchained      = { "es_1h_sword", "es_1h_mace", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer" },
    bw_necromancer    = { "es_1h_sword", "es_1h_mace", "wh_1h_falchion", "dr_1h_axe", "wh_1h_axe", "we_1h_sword", "dr_1h_hammer" },
}

local original_can_wield = {}
local original_can_wield_saved = {}

local function feature_enabled(setting_id, default_value)
    local value = mod:get(setting_id)
    if value == nil then return default_value ~= false end
    return value == true
end

local function apply_weapon_unlocks()
    if not ItemMasterList then return end

    -- Collect every weapon key this mod might touch.
    local all_weapon_keys = {}
    for _, weapons in pairs(weapon_unlock_map) do
        for _, weapon_key in ipairs(weapons) do
            all_weapon_keys[weapon_key] = true
        end
    end

    -- Restore and Save logic
    for weapon_key in pairs(all_weapon_keys) do
        local item = ItemMasterList[weapon_key]
        if item then
            if not original_can_wield_saved[weapon_key] then
                original_can_wield_saved[weapon_key] = true
                if item.can_wield then
                    local original = {}
                    for index, value in ipairs(item.can_wield) do
                        original[index] = value
                    end
                    original_can_wield[weapon_key] = original
                end
            end

            local original = original_can_wield[weapon_key]
            if original then
                if not item.can_wield then item.can_wield = {} end
                while #item.can_wield > 0 do table.remove(item.can_wield) end
                for _, value in ipairs(original) do
                    item.can_wield[#item.can_wield + 1] = value
                end
            else
                item.can_wield = nil
            end
        end
    end

    -- Apply unlocks
    for career, weapons in pairs(weapon_unlock_map) do
        for _, weapon_key in ipairs(weapons) do
            if mod:get("unlock_" .. career .. "_" .. weapon_key) then
                local item = ItemMasterList[weapon_key]
                if item then
                    if not item.can_wield then item.can_wield = {} end
                    local already = false
                    for _, value in ipairs(item.can_wield) do
                        if value == career then already = true; break end
                    end
                    if not already then
                        item.can_wield[#item.can_wield + 1] = career
                    end
                end
            end
        end
    end
end

mod.on_game_state_changed = function(status, state_name)
    mod:info("Weapon Tweaker: Baseline Active")
    apply_weapon_unlocks()
end

mod.on_setting_changed = function(setting_id)
    if setting_id and (setting_id:find("^unlock_") or setting_id == "debug") then
        apply_weapon_unlocks()
    end
end

-- ============================================================
-- DISABLED HOOKS FOR CRASH INVESTIGATION
-- ============================================================
--[[
mod:hook("GearUtils", "create_equipment", ...)
mod:hook("Unit", "node", ...)
mod:hook("Unit", "animation_find_variable", ...)
mod:hook("Unit", "animation_event", ...)
...
]]

-- Install basic backend hooks (UI filtering and can_wield override)
weapon_backend.install(mod, weapon_unlock_map, apply_weapon_unlocks)
