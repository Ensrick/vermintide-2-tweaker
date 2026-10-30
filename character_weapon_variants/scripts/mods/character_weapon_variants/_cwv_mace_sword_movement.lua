-- _cwv_mace_sword_movement.lua -- derived movement for one admitted Mace view.
-- #645: no leases or native-state writes. The style runtime owns one snapshot.
-- Native93dea: helper ground196/air461; status.update288 forbids a getter hook.
-- Owned by: character_weapon_variants.lua. Consumed via the Mace runtime owner.
local M = {}
local type, rawget, pcall, select, HUGE = type, rawget, pcall, select, math.huge
local KEY, TEMPLATE, DIRECTION = "es_1h_sword", "cwv_645_mace_sword_style", "mace_on_empire_sword"
local function field(value, key)
    if type(value) == "table" then return rawget(value, key) end
end
local function identity(item)
    return field(item, "backend_id") or field(item, "ItemId") or field(field(item, "mod_data"), "backend_id")
end
local function finite(value) return type(value) == "number" and value == value and value > -HUGE and value < HUGE end
-- Extension/player/item/registry tables are identities, never __eq policy.
-- Native unit userdata retains its existing engine equality semantics.
local function same_ref(a, b)
    if type(a) == "table" or type(b) == "table" then return rawequal(a, b) end
    return a == b
end
function M.bind(deps)
    local runtime, actor, constructor = assert(deps.runtime), assert(deps.actor), assert(deps.constructor)
    local alive, extensions, local_player = assert(deps.alive), assert(deps.extensions), assert(deps.local_player)
    local weapons, enabled = assert(deps.weapons), assert(deps.enabled)
    local describe, inventory_profile, template = assert(runtime.describe), assert(actor.inventory_profile), assert(constructor.template)
    local function capture(inventory, slot_name, item)
        if enabled() ~= true or (slot_name ~= "slot_melee" and slot_name ~= "slot_ranged")
                or field(item, "name") ~= KEY then return nil end
        local unit, player = field(inventory, "_unit"), local_player()
        if unit == nil or not alive(unit) or not same_ref(field(player, "player_unit"), unit)
                or not same_ref(field(inventory, "player"), player) or field(inventory, "is_bot") ~= false then return nil end
        local ext = extensions(unit)
        local status, csm = field(ext, "status_system"), field(ext, "character_state_machine_system")
        local equipment = field(inventory, "_equipment")
        local slot = field(field(equipment, "slots"), slot_name)
        if not same_ref(field(ext, "inventory_system"), inventory) or not same_ref(field(status, "unit"), unit)
                or not same_ref(field(status, "inventory_extension"), inventory) or not same_ref(field(csm, "unit"), unit)
                or not same_ref(field(csm, "player"), player) or field(equipment, "wielded_slot") ~= slot_name
                or not same_ref(field(equipment, "wielded"), item) or not same_ref(field(slot, "item_data"), item) then return nil end
        local row = describe(runtime, item, nil, function() return inventory_profile(actor, inventory, slot_name, item) end)
        if type(row) ~= "table" or row.item_key ~= KEY or not same_ref(row.item_data, item) or row.family_id ~= "one_handed_swords"
                or field(row.package, "template") ~= TEMPLATE or field(row.package, "style_id") ~= row.style_id or row.identity ~= identity(item)
                or type(row.style_id) ~= "string" or field(field(runtime.store, "items"), row.identity) ~= row.style_id then return nil end
        -- The actual constructor getter performs retained graph validation here,
        -- once at admission, never in factor/ground/air. check() healthy is nil.
        local name, value = template(DIRECTION)
        local registry = weapons()
        if name ~= TEMPLATE or type(value) ~= "table" or not same_ref(field(registry, name), value)
                or not same_ref(field(slot, "item_template"), value) then return nil end
        local profile_fn, career_fn, disabled_fn = player.profile_index, player.career_index, status.is_disabled
        if type(profile_fn) ~= "function" or type(career_fn) ~= "function" or type(disabled_fn) ~= "function" then return nil end
        local profile, career = profile_fn(player), career_fn(player)
        if type(profile) ~= "number" or profile < 1 or profile % 1 ~= 0
                or type(career) ~= "number" or career < 1 or career % 1 ~= 0 then return nil end
        return { unit = unit, player = player, inventory = inventory, status = status, csm = csm, extensions = ext,
            equipment = equipment, slot_name = slot_name, slot = slot, item = item, identity = row.identity, style = row.style_id,
            store = runtime.store, items = runtime.store.items, registry = registry, template = value,
            profile_fn = profile_fn, career_fn = career_fn, profile = profile, career = career,
            inventory_profile = field(inventory, "_profile"), career_name = field(inventory, "_career_name"),
            disabled_fn = disabled_fn, right = field(equipment, "right_hand_wielded_unit"), left = field(equipment, "left_hand_wielded_unit"),
            key = field(item, "key"), cwv_key = field(item, "cwv_key"), item_type = field(item, "item_type") }
    end
    local function eligible(s, mode, first, input, locomotion, unit)
        if enabled() ~= true or type(s) ~= "table" or not same_ref(unit, s.unit) or not alive(unit)
                or (s.slot_name ~= "slot_melee" and s.slot_name ~= "slot_ranged")
                or not same_ref(local_player(), s.player) or not same_ref(field(s.player, "player_unit"), unit) then return false end
        local ext = extensions(unit)
        if not same_ref(ext, s.extensions) or not same_ref(field(ext, "inventory_system"), s.inventory)
                or not same_ref(field(ext, "status_system"), s.status)
                or not same_ref(field(ext, "character_state_machine_system"), s.csm)
                or not same_ref(field(ext, "first_person_system"), first)
                or not same_ref(field(ext, "input_system"), input)
                or not same_ref(field(ext, "locomotion_system"), locomotion) then return false end
        local machine = field(s.csm, "state_machine")
        local state = field(machine, "state_current")
        local name = field(state, "name")
        if field(machine, "state_next") ~= nil or (mode == "ground" and name ~= "walking")
                or (mode == "air" and name ~= "jumping" and name ~= "falling")
                or not same_ref(field(state, "unit"), unit) or not same_ref(field(state, "player"), s.player)
                or not same_ref(field(state, "status_extension"), s.status)
                or not same_ref(field(state, "inventory_extension"), s.inventory)
                or not same_ref(field(state, "first_person_extension"), first)
                or not same_ref(field(state, "input_extension"), input)
                or not same_ref(field(state, "locomotion_extension"), locomotion) then return false end
        if not same_ref(field(s.status, "unit"), unit) or not same_ref(field(s.status, "inventory_extension"), s.inventory)
                or s.status.is_disabled ~= s.disabled_fn or s.disabled_fn(s.status) ~= false
                or s.player.profile_index ~= s.profile_fn or s.player.career_index ~= s.career_fn
                or s.profile_fn(s.player) ~= s.profile or s.career_fn(s.player) ~= s.career then return false end
        local inventory, equipment, item = s.inventory, s.equipment, s.item
        if not same_ref(field(inventory, "_unit"), unit) or not same_ref(field(inventory, "player"), s.player)
                or field(inventory, "is_bot") ~= false or not same_ref(field(inventory, "_profile"), s.inventory_profile)
                or field(inventory, "_career_name") ~= s.career_name
                or not same_ref(field(inventory, "_equipment"), equipment) or field(equipment, "wielded_slot") ~= s.slot_name
                or not same_ref(field(field(equipment, "slots"), s.slot_name), s.slot)
                or not same_ref(field(s.slot, "item_data"), item)
                or not same_ref(field(s.slot, "item_template"), s.template)
                or not same_ref(field(equipment, "wielded"), item)
                or not same_ref(field(equipment, "right_hand_wielded_unit"), s.right)
                or not same_ref(field(equipment, "left_hand_wielded_unit"), s.left) or field(item, "name") ~= KEY
                or identity(item) ~= s.identity or field(item, "key") ~= s.key or field(item, "cwv_key") ~= s.cwv_key
                or field(item, "item_type") ~= s.item_type then return false end
        return same_ref(runtime.store, s.store) and same_ref(field(s.store, "items"), s.items)
            and field(s.items, s.identity) == s.style and same_ref(weapons(), s.registry)
            and same_ref(field(s.registry, TEMPLATE), s.template)
    end
    local O = {}
    function O.capture(inventory, slot_name, item)
        local ok, snapshot = pcall(capture, inventory, slot_name, item)
        return ok and snapshot or nil
    end
    local function factor(snapshot, mode, first, input, locomotion, unit)
        if mode ~= "ground" and mode ~= "air" then return 1 end
        local ok, admitted = pcall(eligible, snapshot, mode, first, input, locomotion, unit)
        return ok and admitted == true and 1.05 or 1
    end
    O.factor = factor
    local function speed_for(snapshot, mode, first, input, locomotion, speed, unit)
        if not finite(speed) then return speed end
        local scaled = speed * factor(snapshot, mode, first, input, locomotion, unit)
        return finite(scaled) and scaled or speed
    end
    function O.ground(snapshot, func, first, input, locomotion, direction, speed, unit, ...)
        speed = speed_for(snapshot, "ground", first, input, locomotion, speed, unit)
        return func(first, input, locomotion, direction, speed, unit, ...)
    end
    function O.air(snapshot, func, first, input, locomotion, speed, unit, ...)
        -- Native jumping184/falling283 pass no optional forced-move timers.
        if select("#", ...) == 0 then speed = speed_for(snapshot, "air", first, input, locomotion, speed, unit) end
        return func(first, input, locomotion, speed, unit, ...)
    end
    return O
end
return M
