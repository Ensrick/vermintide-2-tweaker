-- ============================================================
-- Third-Person Equipment (experimental)
-- ============================================================
-- Inspired by the standalone "Third Person Equipment" mod
-- (Workshop 1387440934). This is a clean reimplementation of the
-- spawn / link / visibility machinery using a small per-item_type
-- attachment table instead of TPE's exhaustive per-career tuning.
--
-- Status: EXPERIMENTAL. Off by default. Positions are deliberately
-- coarse; only weapons that aren't currently wielded are shown on
-- the body. Tuning is per item_type, not per career or skin.
--
-- Caveats vs. the original mod:
--   * No per-career / per-skin position tuning.
--   * No special replace-on-conflict logic (slayer dual axes).
--   * No dwarf-backpack alternate node.
--   * CWV custom-mesh weapons follow item_data.right_hand_unit and
--     should spawn correctly when their 3P unit is in the global
--     package list, but expect rough placement.
--
-- Returns a small API (M.update / M.flush / M.is_enabled) that the
-- main mod file plugs into mod.update and mod.on_setting_changed.
local mod = get_mod("cosmetics_tweaker")

local M = {}

local SPINE       = "j_spine"
local SPINE2      = "j_spine2"
local HIPS        = "j_hips"
local LEFT_LEG    = "j_leftupleg"
local RIGHT_LEG   = "j_rightupleg"

-- ============================================================
-- ATTACHMENT TABLE
-- ============================================================
-- Keyed by item_type. `right` / `left` describe where to mount
-- the corresponding hand's 3P mesh. node = skeleton bone name,
-- position = local offset (xyz), rotation = local euler degrees.
local CATEGORIES = {
    -- 2H melee, weapon high on back angled across right shoulder
    two_handed_back = {
        right = { node = SPINE, position = {-0.05, 0.25, 0.10}, rotation = {-70, 110, -90} },
    },
    -- 1H melee, weapon hanging on right hip
    one_handed_belt = {
        right = { node = HIPS, position = {0.10, -0.05, 0.05}, rotation = {0, 90, 90} },
    },
    -- 1H + shield: weapon on right hip, shield slung over left shoulder
    one_handed_shield = {
        right = { node = HIPS,  position = {0.10, -0.05, 0.05}, rotation = {0, 90, 90} },
        left  = { node = SPINE, position = {-0.05, 0.10, -0.05}, rotation = {-90, 0, 90} },
    },
    -- Dual wield, split between left and right hip
    dual_belt = {
        right = { node = HIPS, position = {0.10, -0.05, 0.05}, rotation = {0, 90, 90} },
        left  = { node = HIPS, position = {-0.10, -0.05, 0.05}, rotation = {0, -90, -90} },
    },
    -- Ranged firearms / crossbows / pistols pair, slung on back
    ranged_back = {
        right = { node = SPINE, position = {-0.05, 0.20, -0.05}, rotation = {-70, 110, 90} },
    },
    -- Bows / staves, slung on back at a slightly different angle
    bow_back = {
        right = { node = SPINE, position = {-0.10, 0.15, 0.00}, rotation = {0, 180, 90} },
    },
    -- Throwables (axes / javelin) on belt right
    throwable_belt = {
        right = { node = HIPS, position = {0.10, -0.10, 0.10}, rotation = {0, 90, 90} },
    },
    -- Consumable potion: small left-hip flask
    potion_hip = {
        left = { node = HIPS, position = {-0.10, -0.05, 0.10}, rotation = {40, 90, 0} },
    },
    -- Consumable grenade: small right-hip pouch
    grenade_hip = {
        right = { node = HIPS, position = {0.10, -0.05, 0.15}, rotation = {40, 90, 0} },
    },
    -- Healthkit: small on back center
    healthkit_back = {
        left = { node = SPINE, position = {0, 0.10, -0.05}, rotation = {0, 90, 0} },
    },
    -- Default fallback when nothing else matches
    default = {
        right = { node = SPINE, position = {0, 0, 0}, rotation = {0, 0, 0} },
        left  = { node = SPINE, position = {0, 0, 0}, rotation = {0, 0, 0} },
    },
}

-- Map vanilla item_type values to a category.
local TYPE_CATEGORY = {
    -- ES (Kruber)
    es_1h_mace               = "one_handed_belt",
    es_1h_sword              = "one_handed_belt",
    es_flail                 = "one_handed_belt",
    es_1h_mace_shield        = "one_handed_shield",
    es_1h_sword_shield       = "one_handed_shield",
    es_1h_sword_shield_breton= "one_handed_shield",
    es_2h_halberd            = "two_handed_back",
    es_2h_heavy_spear        = "two_handed_back",
    es_2h_sword              = "two_handed_back",
    es_2h_sword_executioner  = "two_handed_back",
    es_2h_war_hammer         = "two_handed_back",
    es_bastard_sword         = "two_handed_back",
    es_dual_wield_hammer_sword = "dual_belt",
    es_handgun               = "ranged_back",
    es_repeating_handgun     = "ranged_back",
    es_blunderbuss           = "ranged_back",
    es_deus_01               = "two_handed_back",

    -- BW (Sienna)
    bw_1h_sword              = "one_handed_belt",
    bw_1h_dagger             = "one_handed_belt",
    bw_1h_crowbill           = "one_handed_belt",
    bw_1h_flail_flaming      = "one_handed_belt",
    bw_flame_sword           = "one_handed_belt",
    bw_ghost_scythe          = "two_handed_back",
    bw_morningstar           = "two_handed_back",
    bw_necromancy_staff      = "bow_back",
    bw_staff_beam            = "bow_back",
    bw_staff_firball         = "bow_back",
    bw_staff_flamethrower    = "bow_back",
    bw_staff_geiser          = "bow_back",
    bw_staff_spear           = "bow_back",
    bw_deus_01               = "bow_back",

    -- WH (Saltzpyre)
    wh_1h_axes               = "one_handed_belt",
    wh_1h_falchions          = "one_handed_belt",
    wh_1h_hammer             = "one_handed_belt",
    wh_fencing_sword         = "one_handed_belt",
    wh_2h_billhook           = "two_handed_back",
    wh_2h_hammer             = "two_handed_back",
    wh_2h_sword              = "two_handed_back",
    wh_flail_shield          = "one_handed_shield",
    wh_hammer_book           = "one_handed_belt",
    wh_hammer_shield         = "one_handed_shield",
    wh_dual_hammer           = "dual_belt",
    wh_dual_wield_axe_falchion = "dual_belt",
    wh_brace_of_pisols       = "ranged_back",
    wh_crossbow              = "ranged_back",
    wh_repeating_crossbow    = "ranged_back",
    wh_repeating_pistol      = "ranged_back",
    wh_deus_01               = "two_handed_back",

    -- DR (Bardin)
    dr_1h_axes               = "one_handed_belt",
    dr_1h_hammer             = "one_handed_belt",
    dr_1h_axe_shield         = "one_handed_shield",
    dr_1h_hammer_shield      = "one_handed_shield",
    dr_1h_throwing_axes      = "throwable_belt",
    dr_2h_axes               = "two_handed_back",
    dr_2h_hammer             = "two_handed_back",
    dr_2h_picks              = "two_handed_back",
    dr_cog_hammer            = "two_handed_back",
    dr_dual_axes             = "dual_belt",
    dr_dual_wield_hammers    = "dual_belt",
    dr_handgun               = "ranged_back",
    dr_crossbow              = "ranged_back",
    dr_grudgeraker           = "ranged_back",
    dr_drakegun              = "ranged_back",
    dr_drakefire_pistols     = "ranged_back",
    dr_steam_pistol          = "ranged_back",
    dr_deus_01               = "two_handed_back",
    bardin_engineer_career_skill_weapon       = "ranged_back",
    bardin_engineer_career_skill_weapon_heavy = "ranged_back",

    -- WW (Kerillian)
    ww_1h_sword              = "one_handed_belt",
    ww_dual_swords           = "dual_belt",
    ww_dual_daggers          = "dual_belt",
    ww_sword_and_dagger      = "dual_belt",
    ww_2h_axe                = "two_handed_back",
    ww_2h_sword              = "two_handed_back",
    ww_longbow               = "bow_back",
    ww_shortbow              = "bow_back",
    ww_hagbane               = "bow_back",

    -- WE (Sienna's elf line / Sister of the Thorn etc)
    we_1h_axe                = "one_handed_belt",
    we_spear                 = "one_handed_belt",
    we_1h_spears_shield      = "one_handed_shield",
    we_2h_spear              = "two_handed_back",
    we_dual_wield_daggers    = "dual_belt",
    we_javelin               = "throwable_belt",
    we_life_staff            = "bow_back",
    we_deus_01               = "two_handed_back",

    -- Slot consumables
    potion                   = "potion_hip",
    grenade                  = "grenade_hip",
    healthkit                = "healthkit_back",
}

local function get_def_for(item_data)
    if not item_data or not item_data.item_type then return CATEGORIES.default end
    local cat = TYPE_CATEGORY[item_data.item_type]
    return (cat and CATEGORIES[cat]) or CATEGORIES.default
end

-- ============================================================
-- STATE
-- ============================================================
local current = {
    firstperson = true,
    slot = {},        -- player_unit -> wielded slot_name
    equipment = {},   -- player_unit -> array of i_unit records
    profile = {},     -- player_unit -> profile unit_name (for future tuning)
}
local spawned_units = {}     -- weak set of all units we created
local hooks_installed = false

-- ============================================================
-- HELPERS
-- ============================================================
local function is_enabled()
    return mod:get("tpe_enable") == true
end

local function get_world()
    return Managers.world and Managers.world:world("level_world")
end

local function destroy_unit(unit)
    if unit and Unit.alive(unit) then
        local world = get_world()
        if world then
            World.destroy_unit(world, unit)
        end
    end
end

local function delete_i_unit(i_unit)
    if i_unit.right ~= nil then
        spawned_units[i_unit.right] = nil
        destroy_unit(i_unit.right)
    end
    if i_unit.left ~= nil then
        spawned_units[i_unit.left] = nil
        destroy_unit(i_unit.left)
    end
end

local function delete_units(unit)
    local list = current.equipment[unit]
    if list then
        for _, i_unit in pairs(list) do
            delete_i_unit(i_unit)
        end
        current.equipment[unit] = nil
    end
end

local function delete_all_units()
    for unit, _ in pairs(current.equipment) do
        delete_units(unit)
    end
    -- Catch any orphans
    for u, _ in pairs(spawned_units) do
        destroy_unit(u)
    end
    current.equipment = {}
    spawned_units = {}
end

-- ============================================================
-- SPAWN + LINK
-- ============================================================
local function link_unit(unit, s_unit, item_setting)
    local world = get_world()
    if not world then return end

    local node_name = item_setting.node
    if node_name and Unit.has_node(unit, node_name) then
        local node = Unit.node(unit, node_name)
        World.link_unit(world, s_unit, unit, node)
    else
        -- Fall back to root link; will float at character origin but won't crash
        World.link_unit(world, s_unit, unit, 0)
    end

    local p = item_setting.position
    local pos = (p ~= nil and Vector3(p[1] or 0, p[2] or 0, p[3] or 0)) or Vector3(0, 0, 0)
    Unit.set_local_position(s_unit, 0, pos)

    local r = item_setting.rotation
    local rx = (r and r[1]) or 0
    local ry = (r and r[2]) or 0
    local rz = (r and r[3]) or 0
    local rot = Quaternion.from_euler_angles_xyz(rx, ry, rz)
    Unit.set_local_rotation(s_unit, 0, rot)
end

local function spawn_3p(unit_path, owner_unit, item_setting, item_data)
    local world = get_world()
    if not world then return nil end
    if not unit_path or unit_path == "" then return nil end
    if not Application.can_get("unit", unit_path) then return nil end

    local s_unit
    local ok, err = pcall(function()
        s_unit = World.spawn_unit(world, unit_path)
    end)
    if not ok or not s_unit then
        mod:info("[tpe] spawn failed for %s: %s", tostring(unit_path), tostring(err))
        return nil
    end

    spawned_units[s_unit] = s_unit
    link_unit(owner_unit, s_unit, item_setting)

    local scale_pct = mod:get("tpe_downscale_big_weapons")
    if scale_pct and scale_pct ~= 100 then
        local scale = scale_pct / 100
        Unit.set_local_scale(s_unit, 0, Vector3(scale, scale, scale))
    end

    return s_unit
end

-- ============================================================
-- ADD ITEMS
-- ============================================================
local function resolve_skin_unit(equipment, slot_name, base_unit, side)
    if not WeaponSkins then return base_unit, nil end
    local slot = equipment.slots and equipment.slots[slot_name]
    if not slot or not slot.skin then return base_unit, nil end
    local skin_def = WeaponSkins.skins and WeaponSkins.skins[slot.skin]
    if not skin_def then return base_unit, nil end
    local unit = (side == "right" and skin_def.right_hand_unit) or skin_def.left_hand_unit
    if unit and unit ~= "" then
        return unit, skin_def.material_settings
    end
    return base_unit, skin_def.material_settings
end

local function add_item(unit, slot_name, item_data)
    if not item_data then return end

    -- Skip the wielded slot at first add — set_equipment_visibility will
    -- toggle it later when the player switches off this slot.
    local def_pair = get_def_for(item_data)
    if not def_pair then return end

    local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
    if not inventory_extension then return end
    local equipment = inventory_extension:equipment()

    local right, left, right_path, left_path

    if item_data.right_hand_unit and item_data.right_hand_unit ~= "" and def_pair.right then
        local base = item_data.right_hand_unit
        local skinned_base, mat = resolve_skin_unit(equipment, slot_name, base, "right")
        right_path = (skinned_base or base) .. "_3p"
        right = spawn_3p(right_path, unit, def_pair.right, item_data)
        if right and mat and GearUtils and GearUtils.apply_material_settings then
            pcall(GearUtils.apply_material_settings, right, mat)
        end
    end

    if item_data.left_hand_unit and item_data.left_hand_unit ~= "" and def_pair.left then
        local base = item_data.left_hand_unit
        local skinned_base, mat = resolve_skin_unit(equipment, slot_name, base, "left")
        left_path = (skinned_base or base) .. "_3p"
        left = spawn_3p(left_path, unit, def_pair.left, item_data)
        if left and mat and GearUtils and GearUtils.apply_material_settings then
            pcall(GearUtils.apply_material_settings, left, mat)
        end
    end

    if not right and not left then return end

    current.equipment[unit] = current.equipment[unit] or {}
    table.insert(current.equipment[unit], {
        right = right,
        left = left,
        slot = slot_name,
        right_path = right_path,
        left_path = left_path,
        item_type = item_data.item_type,
        visible = true,
    })
end

local function add_all_items(unit)
    if current.equipment[unit] then return end

    local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
    if not inventory_extension then return end
    local equipment = inventory_extension:equipment()
    if not equipment or not equipment.slots then return end

    for slot_name, slot in pairs(equipment.slots) do
        if slot.item_data then
            add_item(unit, slot_name, slot.item_data)
        end
    end

    -- Initialise wielded slot tracking; default to slot_melee if engine
    -- hasn't reported a wielded slot yet.
    if not current.slot[unit] then
        current.slot[unit] = equipment.wielded_slot or "slot_melee"
    end
end

-- ============================================================
-- VISIBILITY
-- ============================================================
local function set_equipment_visibility(unit, hide)
    local list = current.equipment[unit]
    if not list then return end

    -- For the local player in first-person, hide every holstered mesh
    -- because they're inside the camera and clip badly.
    local player = mod._local_player_safe and mod._local_player_safe(Managers.player)
    if player and player.player_unit and unit == player.player_unit then
        if hide == nil and current.firstperson then
            hide = true
        end
    end

    for _, equip in pairs(list) do
        local should_hide = hide or (equip.slot == current.slot[unit])
        if should_hide then
            if equip.visible ~= false then
                if equip.right then Unit.set_unit_visibility(equip.right, false) end
                if equip.left  then Unit.set_unit_visibility(equip.left,  false) end
                equip.visible = false
            end
        else
            if equip.visible ~= true then
                if equip.right then
                    Unit.set_unit_visibility(equip.right, true)
                    Unit.flow_event(equip.right, "lua_wield")
                    Unit.flow_event(equip.right, "lua_unwield")
                end
                if equip.left then
                    Unit.set_unit_visibility(equip.left, true)
                    Unit.flow_event(equip.left, "lua_wield")
                    Unit.flow_event(equip.left, "lua_unwield")
                end
                equip.visible = true
            end
        end
    end
end

local function wield_equipment(unit, slot_name)
    current.slot[unit] = slot_name
    set_equipment_visibility(unit)
end

-- ============================================================
-- CREATE-IF-NEEDED (per-frame tick)
-- ============================================================
local function is_not_loading()
    if not Managers.package then return true end
    local q1 = Managers.package._queued_async_packages
    local q2 = Managers.package._queue_order
    return (not q1 or #q1 == 0) and (not q2 or #q2 == 0)
end

local function create_items_if_needed()
    if not Managers or not Managers.state or not Managers.state.network then return end
    if not Managers.player then return end
    if not is_not_loading() then return end

    local players = Managers.player:human_and_bot_players()
    if not players then return end

    for _, player in pairs(players) do
        if player then
            local pu = player.player_unit
            if pu and not current.equipment[pu] then
                local profile_sync = Managers.state.network.profile_synchronizer
                local profile_index = profile_sync
                    and profile_sync:profile_by_peer(player:network_id(), player:local_player_id())

                if profile_index and SPProfiles and SPProfiles[profile_index] then
                    current.profile[pu] = SPProfiles[profile_index].unit_name

                    local health_ext = ScriptUnit.has_extension(pu, "health_system")
                    local status_ext = ScriptUnit.has_extension(pu, "status_system")

                    if health_ext and status_ext and health_ext:is_alive() and not status_ext:is_disabled() then
                        add_all_items(pu)
                        set_equipment_visibility(pu)
                    end
                end
            end
        end
    end
end

-- ============================================================
-- HOOKS
-- ============================================================
local function install_hooks()
    if hooks_installed then return end
    hooks_installed = true

    mod:hook_safe("PlayerUnitFirstPerson", "set_first_person_mode", function(self, active)
        if not is_enabled() then return end
        current.firstperson = active
        set_equipment_visibility(self.unit, active)
    end)

    mod:hook_safe("SimpleInventoryExtension", "wield", function(self, slot_name)
        if not is_enabled() then return end
        wield_equipment(self._unit, slot_name)
    end)
    mod:hook_safe("SimpleHuskInventoryExtension", "wield", function(self, slot_name)
        if not is_enabled() then return end
        wield_equipment(self._unit, slot_name)
    end)

    mod:hook_safe("SimpleInventoryExtension", "destroy_slot", function(self)
        if not is_enabled() then return end
        delete_units(self._unit)
    end)
    mod:hook_safe("SimpleInventoryExtension", "destroy", function(self)
        if not is_enabled() then return end
        delete_units(self._unit)
    end)
    mod:hook_safe("SimpleHuskInventoryExtension", "destroy_slot", function(self)
        if not is_enabled() then return end
        delete_units(self._unit)
    end)
    mod:hook_safe("SimpleHuskInventoryExtension", "destroy", function(self)
        if not is_enabled() then return end
        delete_units(self._unit)
    end)

    mod:hook_safe("PlayerUnitHealthExtension", "die", function(self)
        if not is_enabled() then return end
        delete_units(self.unit)
    end)
end

-- ============================================================
-- PUBLIC API
-- ============================================================
function M.update(dt)
    if not is_enabled() then return end
    create_items_if_needed()
end

function M.flush()
    delete_all_units()
    current.slot = {}
    current.profile = {}
end

function M.on_setting_changed(setting_id)
    -- Any TPE setting change drops all units so they respawn with the
    -- new geometry / scale on the next tick.
    if setting_id == "tpe_enable"
        or setting_id == "tpe_downscale_big_weapons"
        or setting_id == "tpe_show_self_in_3p"
    then
        M.flush()
    end
end

install_hooks()

return M
