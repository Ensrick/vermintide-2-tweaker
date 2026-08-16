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

-- #948 groups live compatibility by the third-person body/state-machine that
-- renders the weapon.  Career-level availability is still counted separately:
-- a receiver cell cannot be promoted merely because one sibling career works.
M.receiver_groups = {
    { key = "kruber", name = "Kruber", careers = {
        "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
    } },
    { key = "bardin", name = "Bardin", careers = {
        "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer",
    } },
    { key = "kerillian", name = "Kerillian", careers = {
        "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
    } },
    { key = "saltzpyre", name = "Saltzpyre", careers = {
        "wh_captain", "wh_bountyhunter", "wh_zealot",
    } },
    { key = "warrior_priest", name = "Warrior Priest", careers = {
        "wh_priest",
    } },
    { key = "sienna", name = "Sienna", careers = {
        "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
    } },
}

M.initial_cell_state = "U"

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

local function _audit_list(list, expected)
    local seen = {}
    local duplicates = 0
    for _, key in ipairs(type(list) == "table" and list or {}) do
        if seen[key] then duplicates = duplicates + 1 end
        seen[key] = true
    end
    local missing = 0
    for _, key in ipairs(expected) do
        if not seen[key] then missing = missing + 1 end
    end
    return missing, duplicates
end

-- Pure structural census for the #948 live-test surface.  Every cell is U by
-- construction.  Static donor maps, native prefixes, picker membership, and
-- historical wired rows are routing evidence only and are deliberately
-- absent from this result.
function M.census(unlock_map, cwv_catalog)
    local result = {
        state = M.initial_cell_state,
        base_weapons = #M.all_weapons,
        careers = #M.careers,
        base_cells = 0,
        untested = 0,
        missing = 0,
        duplicates = 0,
        cwv_variants = type(cwv_catalog) == "table" and #cwv_catalog or 0,
        cwv_cells = 0,
        groups = {},
    }

    for _, group in ipairs(M.receiver_groups) do
        local row = {
            key = group.key,
            name = group.name,
            careers = #group.careers,
            weapons = #M.all_weapons,
            cells = #group.careers * #M.all_weapons,
            state = M.initial_cell_state,
            untested = #group.careers * #M.all_weapons,
            missing = 0,
            duplicates = 0,
        }
        for _, career in ipairs(group.careers) do
            local missing, duplicates = _audit_list(
                unlock_map and unlock_map[career], M.all_weapons)
            row.missing = row.missing + missing
            row.duplicates = row.duplicates + duplicates
        end
        result.groups[#result.groups + 1] = row
        result.base_cells = result.base_cells + row.cells
        result.untested = result.untested + row.untested
        result.missing = result.missing + row.missing
        result.duplicates = result.duplicates + row.duplicates
    end

    if type(cwv_catalog) == "table" then
        local expected_careers = {}
        for _, career in ipairs(M.careers) do
            expected_careers[#expected_careers + 1] = career.key
        end
        for _, variant in ipairs(cwv_catalog) do
            local missing, duplicates = _audit_list(
                variant.careers, expected_careers)
            result.missing = result.missing + missing
            result.duplicates = result.duplicates + duplicates
        end
        result.cwv_cells = #cwv_catalog * #M.careers
        result.untested = result.untested + result.cwv_cells
    end

    return result
end

function M.receiver_census(census, receiver_key)
    for _, row in ipairs(census and census.groups or {}) do
        if row.key == receiver_key then return row end
    end
    return nil
end

-- Issue #183: named audit of the complete Kruber ranged Availability surface.
-- Drives the SAME runtime owners Mod Tweaker renders: the expanded unlock map,
-- the published raw labels (#159/#408), the #611 master-bucket maps built by
-- _wt_master_toggles, and the #108 wt_port_status metadata mirror. The fixed
-- source-group order is the #611 RainReligion amendment
-- (Kruber/Bardin/Kerillian/Saltzpyre/Sienna) enforced via env.source_order_index.
-- Pure: every collaborator arrives via `env`; returns nil when the contract
-- holds, else one bounded failure string.
function M.kruber_ranged_contract(env)
    env = env or {}
    local unlock_map = env.unlock_map
    local loc_raw = env.loc_raw
    local order_by_leaf = env.master_order_by_leaf
    local master_children = env.master_children
    local port_status = env.port_status
    if type(unlock_map) ~= "table" then return "unlock map unavailable" end
    if type(loc_raw) ~= "table" then return "raw localization unavailable" end
    if type(order_by_leaf) ~= "table" or type(master_children) ~= "table" then
        return "master bucket maps unavailable"
    end
    if type(port_status) ~= "table" then return "port status owner unavailable" end
    local kruber_careers
    for _, group in ipairs(M.receiver_groups) do
        if group.key == "kruber" then kruber_careers = group.careers end
    end
    for _, career in ipairs(kruber_careers or {}) do
        local leaf_id = "ranged_" .. career
        local masters = order_by_leaf[leaf_id]
        if type(masters) ~= "table" or #masters == 0 then
            return leaf_id .. " has no source-character buckets"
        end
        local seen, seen_count, prior_rank = {}, 0, 0
        for _, master_id in ipairs(masters) do
            local mcareer, slot, src = env.parse_master_id(master_id)
            if mcareer ~= career or slot ~= "ranged" then
                return tostring(master_id) .. " escaped " .. leaf_id
            end
            local rank = env.source_order_index(src)
            if not rank or rank <= prior_rank then
                return leaf_id .. " breaks the fixed #611 source order at " .. tostring(src)
            end
            prior_rank = rank
            local prior_label
            for _, child_id in ipairs(master_children[master_id] or {}) do
                local weapon_key = child_id:match("^unlock_" .. career .. "_(.+)$")
                if not weapon_key then
                    return tostring(child_id) .. " is not a " .. career .. " unlock row"
                end
                if M.weapon_slot[weapon_key] ~= "ranged" then
                    return child_id .. " is not a ranged weapon row"
                end
                if seen[weapon_key] then return leaf_id .. " duplicates " .. weapon_key end
                seen[weapon_key] = true
                seen_count = seen_count + 1
                local entry = loc_raw[child_id]
                local label = type(entry) == "table" and entry.en
                if type(label) ~= "string" or label == "" then
                    return child_id .. " has no English display label"
                end
                if label == weapon_key or label == child_id or label:find("^%l%l_") then
                    return child_id .. " leaks an internal key: " .. label
                end
                if label:find("[", 1, true) then
                    return child_id .. " carries a retired lifecycle tag: " .. label
                end
                if env.source_char_of(child_id) ~= src then
                    return child_id .. " sits in the wrong source group " .. tostring(src)
                end
                local lower = string.lower(label)
                if prior_label and lower < prior_label then
                    return leaf_id .. "/" .. src .. " is not alphabetical at " .. label
                end
                prior_label = lower
                local redirect = port_status.redirect_target(career, weapon_key)
                local substitute = port_status.model_substitute(career, weapon_key)
                if redirect ~= nil and (type(redirect) ~= "string" or redirect == "") then
                    return child_id .. " has a malformed redirect label"
                end
                if substitute ~= nil and (type(substitute) ~= "string" or substitute == "") then
                    return child_id .. " has a malformed model-substitute label"
                end
                if port_status.routing_state(career, weapon_key) == "native"
                        and (redirect or substitute) then
                    return child_id .. " invents metadata for a native weapon"
                end
            end
        end
        local expected = 0
        for _, weapon_key in ipairs(unlock_map[career] or {}) do
            if M.weapon_slot[weapon_key] == "ranged" then
                expected = expected + 1
                if not seen[weapon_key] then
                    return leaf_id .. " is missing " .. weapon_key
                end
            end
        end
        if expected == 0 then return leaf_id .. " has an empty unlock map" end
        if seen_count ~= expected then
            return leaf_id .. " renders rows outside the unlock map"
        end
    end
    -- Concrete #108 anchors on the Kruber ranged surface: the shipped pistol
    -- model substitutes and staff redirects must stay exact, and a native row
    -- must stay bare.
    local anchors = {
        { "model_substitute", "wh_brace_of_pistols", "Repeater Handgun" },
        { "model_substitute", "wh_repeating_pistols", "Repeater Handgun" },
        { "redirect_target", "bw_skullstaff_beam", "Empire Greathammer" },
        { "redirect_target", "bw_necromancy_staff", "Empire Greathammer" },
        { "redirect_target", "es_handgun", nil },
        { "model_substitute", "es_longbow", nil },
    }
    for _, row in ipairs(anchors) do
        local got = port_status[row[1]]("es_mercenary", row[2])
        if got ~= row[3] then
            return "es_mercenary " .. row[2] .. " " .. row[1] .. " = " .. tostring(got)
                .. " (want " .. tostring(row[3]) .. ")"
        end
    end
    return nil
end

return M
