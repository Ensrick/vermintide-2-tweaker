-- Dev-only universal availability policy for issue #948.
--
-- The public beta keeps its curated receiver lists. The friends-only dev mod
-- deliberately exposes the complete 83-weapon base roster to all 20 careers so
-- live testing can proceed independently of 3P animation readiness. This module
-- also broadens the bounded CWV catalog without making newly exposed receivers
-- default-on. Verified #368 conditional representatives remain owned by the
-- existing availability policy; this module never clears that ownership map.

local M = {}

M.careers = {
    { key = "es_mercenary",      character = "kruber",     name = "Mercenary" },
    { key = "es_huntsman",       character = "kruber",     name = "Huntsman" },
    { key = "es_knight",         character = "kruber",     name = "Foot Knight" },
    { key = "es_questingknight", character = "kruber",     name = "Grail Knight" },
    { key = "dr_ranger",         character = "bardin",     name = "Ranger Veteran" },
    { key = "dr_ironbreaker",    character = "bardin",     name = "Ironbreaker" },
    { key = "dr_slayer",         character = "bardin",     name = "Slayer" },
    { key = "dr_engineer",       character = "bardin",     name = "Outcast Engineer" },
    { key = "we_waywatcher",     character = "kerillian",  name = "Waystalker" },
    { key = "we_maidenguard",    character = "kerillian",  name = "Handmaiden" },
    { key = "we_shade",          character = "kerillian",  name = "Shade" },
    { key = "we_thornsister",    character = "kerillian",  name = "Sister of the Thorn" },
    { key = "wh_captain",        character = "saltzpyre",  name = "Witch Hunter Captain" },
    { key = "wh_bountyhunter",   character = "saltzpyre",  name = "Bounty Hunter" },
    { key = "wh_zealot",         character = "saltzpyre",  name = "Zealot" },
    { key = "wh_priest",         character = "saltzpyre",  name = "Warrior Priest" },
    { key = "bw_adept",          character = "sienna",     name = "Battle Wizard" },
    { key = "bw_scholar",        character = "sienna",     name = "Pyromancer" },
    { key = "bw_unchained",      character = "sienna",     name = "Unchained" },
    { key = "bw_necromancer",    character = "sienna",     name = "Necromancer" },
}

M.melee_weapons = {
    "bw_1h_crowbill", "bw_1h_flail_flaming", "bw_1h_mace", "bw_dagger",
    "bw_flame_sword", "bw_ghost_scythe", "bw_sword",
    "dr_1h_axe", "dr_1h_hammer", "dr_2h_axe", "dr_2h_cog_hammer",
    "dr_2h_hammer", "dr_2h_pick", "dr_dual_wield_axes",
    "dr_dual_wield_hammers", "dr_shield_axe", "dr_shield_hammer",
    "es_1h_flail", "es_1h_mace", "es_1h_sword", "es_2h_hammer",
    "es_2h_heavy_spear", "es_2h_sword", "es_2h_sword_executioner",
    "es_bastard_sword", "es_deus_01", "es_dual_wield_hammer_sword",
    "es_halberd", "es_mace_shield", "es_sword_shield",
    "es_sword_shield_breton",
    "we_1h_axe", "we_1h_spears_shield", "we_1h_sword", "we_2h_axe",
    "we_2h_sword", "we_dual_wield_daggers", "we_dual_wield_sword_dagger",
    "we_dual_wield_swords", "we_spear",
    "wh_1h_axe", "wh_1h_falchion", "wh_1h_hammer", "wh_2h_billhook",
    "wh_2h_hammer", "wh_2h_sword", "wh_dual_hammer",
    "wh_dual_wield_axe_falchion", "wh_fencing_sword", "wh_flail_shield",
    "wh_hammer_book", "wh_hammer_shield",
}

M.ranged_weapons = {
    "bw_deus_01", "bw_necromancy_staff", "bw_skullstaff_beam",
    "bw_skullstaff_fireball", "bw_skullstaff_flamethrower",
    "bw_skullstaff_geiser", "bw_skullstaff_spear",
    "dr_1h_throwing_axes", "dr_crossbow", "dr_deus_01", "dr_drake_pistol",
    "dr_drakegun", "dr_handgun", "dr_rakegun", "dr_steam_pistol",
    "es_blunderbuss", "es_handgun", "es_longbow", "es_repeating_handgun",
    "we_crossbow_repeater", "we_deus_01", "we_javelin", "we_life_staff",
    "we_longbow", "we_shortbow", "we_shortbow_hagbane",
    "wh_brace_of_pistols", "wh_crossbow", "wh_crossbow_repeater",
    "wh_deus_01", "wh_repeating_pistols",
}

M.all_weapons = {}
M.weapon_slot = {}
for _, key in ipairs(M.melee_weapons) do
    M.all_weapons[#M.all_weapons + 1] = key
    M.weapon_slot[key] = "melee"
end
for _, key in ipairs(M.ranged_weapons) do
    M.all_weapons[#M.all_weapons + 1] = key
    M.weapon_slot[key] = "ranged"
end

local function _copy(list)
    local result = {}
    for _, value in ipairs(list or {}) do result[#result + 1] = value end
    return result
end

local function _set(list)
    local result = {}
    for _, value in ipairs(list or {}) do result[value] = true end
    return result
end

function M.expand_unlock_map(map)
    for _, career in ipairs(M.careers) do
        local list = map[career.key] or {}
        map[career.key] = list
        local seen = _set(list)
        for _, weapon_key in ipairs(M.all_weapons) do
            if not seen[weapon_key] then
                list[#list + 1] = weapon_key
                seen[weapon_key] = true
            end
        end
    end
    return map
end

-- CWV owns its authored careers. WT dev owns every additional receiver while
-- CWV is active and removes only those additions when CWV goes away.
function M.expand_cwv_catalog(catalog)
    for _, variant in ipairs(catalog or {}) do
        local original_careers = _copy(variant.careers)
        if type(variant.default_careers) ~= "table" then
            variant.default_careers = _copy(original_careers)
        end
        if type(variant.authored_careers) ~= "table" then
            variant.authored_careers = _copy(original_careers)
        end
        local authored = _set(variant.authored_careers)
        variant.careers = {}
        variant.conditional_careers = {}
        for _, career in ipairs(M.careers) do
            variant.careers[#variant.careers + 1] = career.key
            if not authored[career.key] then
                variant.conditional_careers[#variant.conditional_careers + 1] = career.key
            end
        end
    end
    return catalog
end

local function _index_widgets(nodes, index)
    for _, node in ipairs(nodes or {}) do
        if type(node) == "table" then
            if type(node.setting_id) == "string" then index[node.setting_id] = node end
            _index_widgets(node.sub_widgets, index)
        end
    end
end

-- Add only missing rows. Existing native/curated defaults remain unchanged;
-- every newly exposed receiver is an explicit default-off testing choice.
function M.ensure_base_widgets(data, map)
    local roots = data and data.options and data.options.widgets
    if type(roots) ~= "table" then return 0 end
    local index = {}
    _index_widgets(roots, index)
    local added = 0
    for _, career in ipairs(M.careers) do
        for _, slot in ipairs({ "melee", "ranged" }) do
            local leaf_id = slot .. "_" .. career.key
            local leaf = index[leaf_id]
            if not leaf then
                local parent = index[career.character .. "_" .. slot .. "_group"]
                if parent then
                    parent.sub_widgets = parent.sub_widgets or {}
                    leaf = { setting_id = leaf_id, type = "group", sub_widgets = {} }
                    parent.sub_widgets[#parent.sub_widgets + 1] = leaf
                    index[leaf_id] = leaf
                end
            end
            if leaf then
                leaf.sub_widgets = leaf.sub_widgets or {}
                for _, weapon_key in ipairs(map[career.key] or {}) do
                    if M.weapon_slot[weapon_key] == slot then
                        local setting_id = "unlock_" .. career.key .. "_" .. weapon_key
                        if not index[setting_id] then
                            local row = {
                                setting_id = setting_id,
                                type = "checkbox",
                                default_value = false,
                            }
                            leaf.sub_widgets[#leaf.sub_widgets + 1] = row
                            index[setting_id] = row
                            added = added + 1
                        end
                    end
                end
            end
        end
    end
    return added
end

function M.ensure_base_localization(loc)
    local labels = {}
    for _, weapon_key in ipairs(M.all_weapons) do
        for _, career in ipairs(M.careers) do
            local entry = loc["unlock_" .. career.key .. "_" .. weapon_key]
            if type(entry) == "table" and type(entry.en) == "string" then
                labels[weapon_key] = entry.en
                break
            end
        end
    end
    for _, career in ipairs(M.careers) do
        loc["melee_" .. career.key] = loc["melee_" .. career.key]
            or { en = "Melee: " .. career.name }
        loc["ranged_" .. career.key] = loc["ranged_" .. career.key]
            or { en = "Ranged: " .. career.name }
        for _, weapon_key in ipairs(M.all_weapons) do
            local setting_id = "unlock_" .. career.key .. "_" .. weapon_key
            if not loc[setting_id] then
                loc[setting_id] = { en = labels[weapon_key] or weapon_key }
            end
        end
    end
    return labels
end

return M
