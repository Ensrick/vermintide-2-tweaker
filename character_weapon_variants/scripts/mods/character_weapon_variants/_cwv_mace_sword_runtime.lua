-- _cwv_mace_sword_runtime.lua -- one admitted local-human movement snapshot.
-- Owns two native movement adapters and the post-ownership capture boundary.
-- No buff, RPC, unit write, per-frame graph walk or second inventory hook.
-- Owned by: character_weapon_variants.lua. Consumed via the Mace family owner.
local M = {}
local function pack(...) return { n = select("#", ...), ... } end
function M.install(mod, deps)
    local runtime, actor = assert(deps.runtime), assert(deps.actor)
    local CharacterStateHelper, units, script = assert(deps.helper), assert(deps.units), assert(deps.script)
    local managers, constructor = assert(deps.managers), assert(deps.constructor)
    local weapons = assert(deps.weapons or function() return Weapons end)
    local native_set, snapshot, frame = assert(runtime.set_item_style), nil, nil
    local enabled, hooks = false, 0
    local function local_player()
        local current = managers()
        local pm = current and current.player
        return pm and pm:local_player(1) or nil
    end
    local function current_inventory()
        local player = local_player()
        local unit = player and player.player_unit
        if not unit or not units.alive(unit) then return nil end
        local extensions = script.extensions(unit)
        return extensions and extensions.inventory_system or nil
    end
    local O = {}
    local movement = deps.movement_bind({
        runtime = runtime, actor = actor, constructor = constructor,
        alive = units.alive, extensions = script.extensions, local_player = local_player,
        weapons = weapons,
        enabled = function() return enabled end,
    })
    local capture, ground, air = assert(movement.capture), assert(movement.ground), assert(movement.air)
    function O:invalidate_inventory(inventory, expected_slot)
        if expected_slot ~= nil then
            local equipment = type(inventory) == "table" and rawget(inventory, "_equipment")
            if type(equipment) ~= "table" or rawget(equipment, "wielded_slot") ~= expected_slot then return false end
        end
        if snapshot and rawequal(snapshot.inventory, inventory) then snapshot = nil end
    end
    function O:refresh(inventory, expected_slot)
        if not enabled or frame then return false end
        local ok, current = pcall(current_inventory)
        if not ok or current == nil then snapshot = nil; return false end
        -- A late callback for a destroyed extension must not clear a newer unit.
        if not rawequal(inventory, current) then return false end
        local equipment = rawget(current, "_equipment")
        local slot_name = equipment and equipment.wielded_slot
        if expected_slot ~= nil and slot_name ~= expected_slot then return false end
        snapshot = nil
        local slot = equipment and equipment.slots and equipment.slots[slot_name]
        snapshot = slot and capture(current, slot_name, slot.item_data) or nil
        return snapshot ~= nil
    end
    function O:refresh_current()
        local ok, inventory = pcall(current_inventory)
        if not ok or inventory == nil then snapshot = nil; return false end
        return self:refresh(inventory)
    end
    function O:clear() snapshot = nil end
    function O:set_enabled(value)
        enabled = value == true
        snapshot = nil
        if enabled then self:refresh_current() end
    end
    function O:before_style_commit(row, desired)
        if desired == row.style_id then return end
        -- This callback is immediately before the actual store write. Preflight
        -- refusals never invalidate a still-installed healthy style.
        if snapshot and snapshot.identity == row.identity then
            snapshot = nil
            if frame then frame.dirty = true end
        else
            local ok, inventory = pcall(current_inventory)
            local equipment = ok and inventory and inventory._equipment
            local slot_name = equipment and equipment.wielded_slot
            local slot = equipment and equipment.slots and equipment.slots[slot_name]
            if slot and rawequal(slot.item_data, row.item_data) then
                snapshot = nil
                if frame then frame.dirty = true end
            end
        end
    end
    local function set_item_style(self, ...)
        local active = { parent = frame, dirty = false }
        frame = active
        local result = pack(pcall(native_set, self, ...))
        frame = active.parent
        if active.dirty then
            if frame then frame.dirty = true end
            snapshot = nil
            -- Rollback/error cannot re-admit. A later native wield/init/resync
            -- must prove the repaired installed template independently.
            if result[1] and result[2] == true and frame == nil then O:refresh_current() end
        end
        if not result[1] then error(result[2], 0) end
        return unpack(result, 2, result.n)
    end
    runtime.set_item_style = set_item_style
    local function current_snapshot()
        local s = snapshot
        if s then
            local ok, current_root = pcall(weapons)
            local slots = rawget(s.equipment, "slots")
            if not ok or not rawequal(current_root, s.registry)
                    or (s.slot_name ~= "slot_melee" and s.slot_name ~= "slot_ranged")
                    or type(slots) ~= "table" or not rawequal(rawget(slots, s.slot_name), s.slot)
                    or not rawequal(rawget(s.slot, "item_template"), s.template)
                    or not rawequal(rawget(s.registry, "cwv_645_mace_sword_style"), s.template) then
                snapshot = nil
            end
        end
        return snapshot
    end
    -- Fresh source census has no CWV or either WT hook on these pairs.
    mod:hook(CharacterStateHelper, "move_on_ground", function(func, ...)
        return ground(current_snapshot(), func, ...)
    end)
    hooks = hooks + 1
    mod:hook(CharacterStateHelper, "move_in_air", function(func, ...)
        return air(current_snapshot(), func, ...)
    end)
    hooks = hooks + 1
    -- Initial GO sync is synchronous inside spawn_network_unit, before native
    -- assign_unit_ownership sets player.player_unit. No per-frame retry.
    -- Fresh CWV census: this is the sole hook on this class/method pair.
    mod:hook_safe("PlayerManager", "assign_unit_ownership", function(manager, unit, player, is_player_unit)
        if not enabled or frame or is_player_unit ~= true or type(player) ~= "table" then return end
        local ok, current = pcall(managers)
        if not ok or type(current) ~= "table" or not rawequal(rawget(current, "player"), manager) then return end
        local found, local_owner = pcall(local_player)
        if not found or not rawequal(local_owner, player) then return end
        local assigned = rawget(player, "player_unit")
        if type(assigned) == "table" or type(unit) == "table" then
            if not rawequal(assigned, unit) then return end
        elseif assigned ~= unit then
            return
        end
        O:refresh_current()
    end)
    hooks = hooks + 1
    function O:check()
        if hooks ~= 3 or runtime.set_item_style ~= set_item_style then
            return "#645 Mace movement/style wrapper disconnected"
        end
    end
    return O
end
return M
