local mod = get_mod("wt_dev")
local WT = mod._wt
local Policy = WT.flamestorm_fx_policy
local unit_career_name = WT.unit_career_name

-- #400 source audit:
-- * The owner action uses the universal first-person rig for its gameplay aim
--   and owner-local particle (action_flamethrower.lua:64-89,226-228).
-- * Observer 3P particles are created and moved from the 3P weapon fx_muzzle
--   rotation (weapon_system.lua:470-487,744-774). A receiver-native substitute
--   pose can therefore point the visual away from the replicated aim.
-- Keep the authored muzzle POSITION, but make its ROTATION follow the same
-- network aim_direction used elsewhere in WeaponSystem (weapon_system.lua:345).

local reported_units = setmetatable({}, { __mode = "k" })

local function target_slot_data(unit)
    if not unit or not Unit.alive(unit) then return nil end
    local inventory = ScriptUnit.has_extension(unit, "inventory_system")
    if not inventory then return nil end
    local slot_name = inventory:get_wielded_slot_name()
    local slot_data = slot_name and inventory:get_slot_data(slot_name)
    local item_data = slot_data and slot_data.item_data
    local career_name = unit_career_name(unit)
    if not item_data or not Policy.is_target(career_name, item_data.template) then return nil end
    return slot_data, career_name
end

local function correct_synced_fx(weapon_system, unit, data, unit_id)
    if not data or not data.flamethrower_effect then return false end
    local weapon_unit = data.weapon_unit
    if not weapon_unit or not Unit.alive(weapon_unit) then return false end
    local _, career_name = target_slot_data(unit)
    if not career_name then return false end

    local game = weapon_system.game
    if not game or not unit_id then return false end
    local aim_direction = GameSession.game_object_field(game, unit_id, "aim_direction")
    if not aim_direction or Vector3.length_squared(aim_direction) <= 0.000001 then return false end

    -- Vanilla already resolves this exact node immediately before our post-hook;
    -- retaining that position preserves the staff-tip attachment. Only the
    -- particle orientation changes, so damage, weapon transforms, and native
    -- Sienna presentation remain untouched.
    local muzzle_node = Unit.node(weapon_unit, "fx_muzzle")
    local muzzle_position = Unit.world_position(weapon_unit, muzzle_node)
    local aim_rotation = Quaternion.look(Vector3.normalize(aim_direction))
    World.move_particles(weapon_system.world, data.flamethrower_effect, muzzle_position, aim_rotation)

    if not reported_units[unit] then
        reported_units[unit] = true
        pcall(printf, "[wt:400] applied career=%s template=%s source=replicated_aim",
            career_name, Policy.TEMPLATE)
    end
    return true
end

-- Hook pre-flight: no existing wt hook on either WeaponSystem method. The BR
-- module's dormant flamethrower hook targets ActionFlamethrower._select_targets,
-- a different class/method pair.
mod:safe_hook_safe("WeaponSystem", "rpc_start_flamethrower", function(self, channel_id, unit_id)
    local unit = self.unit_storage and self.unit_storage:unit(unit_id)
    local data = unit and self._flamethrower_particle_effects[unit]
    correct_synced_fx(self, unit, data, unit_id)
end)

-- Vanilla re-applies the pose-derived muzzle rotation every frame, so this
-- post-hook must re-assert replicated aim after every vanilla update. It emits
-- only the one apply marker above, never per-frame logging.
mod:safe_hook_safe("WeaponSystem", "update_synced_flamethrower_particle_effects", function(self)
    local effects = self._flamethrower_particle_effects
    local network_manager = self.network_manager
    if type(effects) ~= "table" or not network_manager then return end
    for unit, data in pairs(effects) do
        local unit_id = network_manager:unit_game_object_id(unit)
        correct_synced_fx(self, unit, data, unit_id)
    end
end)

WT.flamestorm_fx_correct = correct_synced_fx

WT.rt_register("issue400_cross_career_flamestorm_fx_uses_replicated_aim", function()
    if not Policy.is_target("es_mercenary", Policy.TEMPLATE) then
        return "cross-career Flamestorm policy is not active"
    end
    if Policy.is_target("bw_adept", Policy.TEMPLATE) then
        return "native Sienna Flamestorm must remain untouched"
    end
    if type(WT.flamestorm_fx_correct) ~= "function" then
        return "observer FX correction is not wired"
    end
end)
