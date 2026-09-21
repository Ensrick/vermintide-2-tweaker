-- _mp_fresh_profile_state.lua - MP-owned isolated profile state (issue #840).
--
-- Pure module: no VMF, engine, or Managers access. Every engine table the
-- seed or hydration needs (ItemMasterList, CareerSettings, the Chaos Wastes
-- default-loadout tables, power constants) arrives through an `env` table so
-- the offline suite can drive the exact production code.
--
-- Profile shape (persisted under M.SETTING_KEY by the runtime):
--   { schema = 1, generation = N, slices = { items = <slice> } }
-- Items slice (seeded exactly once per generation):
--   { generation = N, revision = R,
--     inventory = { [backend_id] = { ItemId, ItemInstanceId, power_level } },
--     cosmetics = { [backend_id] = { ItemId, ItemInstanceId } },
--     careers   = { [career] = { selected = i, loadouts = { [i] = { slot = value } } } },
--     pose_skins = { [parent_item] = skin_key } }
-- Loadout values follow vanilla: equipment slots hold backend ids, cosmetic
-- and pose slots hold item keys [src: backend_interface_item_playfab.lua:657-665].
local M = {}

M.SCHEMA = 1
M.SETTING_KEY = "mp_profile_v1"
M.SLICE = "items"
M.ID_PREFIX = "mp840_"

-- [src: backend_interface_item_playfab.lua:25-35]
M.LOADOUT_SLOTS = {
    "slot_ranged", "slot_melee", "slot_skin", "slot_hat", "slot_necklace",
    "slot_ring", "slot_trinket_1", "slot_frame", "slot_pose",
}
M.WEAPON_SLOTS = { slot_melee = "melee", slot_ranged = "ranged" }
M.JEWELLERY_SLOTS = { slot_necklace = "necklace", slot_ring = "ring", slot_trinket_1 = "trinket" }
M.COSMETIC_SLOTS = { slot_skin = "skin", slot_hat = "hat", slot_frame = "frame" }
M.EQUIPMENT_SLOT_TYPES = { melee = true, ranged = true, necklace = true, ring = true, trinket = true }

local function deep_copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do copy[deep_copy(key, seen)] = deep_copy(child, seen) end
    return copy
end
M.copy = deep_copy

local function sorted_keys(t)
    local keys = {}
    for key in pairs(t or {}) do
        if type(key) == "string" then keys[#keys + 1] = key end
    end
    table.sort(keys)
    return keys
end

local function count(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function is_index(value)
    return type(value) == "number" and value == math.floor(value) and value >= 1
end

-- ============================================================
-- Profile envelope
-- ============================================================
function M.new_profile(previous)
    local generation = type(previous) == "table" and tonumber(previous.generation) or 0
    if generation ~= generation or generation < 0 or generation == math.huge then generation = 0 end
    return { schema = M.SCHEMA, generation = math.floor(generation) + 1, slices = {} }
end

-- Returns the stored profile when it is well formed, otherwise a fresh
-- envelope one generation past whatever was stored (so a corrupt record can
-- never be mistaken for a seeded one).
function M.normalize(raw)
    if type(raw) ~= "table" or raw.schema ~= M.SCHEMA or not is_index(raw.generation)
            or type(raw.slices) ~= "table" then
        return M.new_profile(raw), (raw == nil) and "initial" or "malformed"
    end
    return raw, nil
end

function M.items_slice(profile)
    local slice = type(profile) == "table" and type(profile.slices) == "table"
        and profile.slices[M.SLICE] or nil
    if type(slice) ~= "table" or slice.generation ~= profile.generation
            or not is_index(slice.revision) or type(slice.inventory) ~= "table"
            or type(slice.cosmetics) ~= "table" or type(slice.careers) ~= "table" then
        return nil
    end
    return slice
end

function M.items_seeded(profile)
    return M.items_slice(profile) ~= nil
end

-- ============================================================
-- Seed
-- ============================================================
local function item_data(env, key)
    local list = env.item_master_list
    if type(list) ~= "table" or type(key) ~= "string" then return nil end
    local data = rawget(list, key)
    return type(data) == "table" and data or nil
end

-- Jewellery shares the CanWieldAllItemTemplates career list; an absent or
-- empty list is treated as wieldable-by-all, matching the shared-table
-- contract [src: item_master_list.lua:7-27].
local function wieldable(data, career)
    local can_wield = data.can_wield
    if type(can_wield) ~= "table" or #can_wield == 0 then return true end
    for _, name in ipairs(can_wield) do
        if name == career then return true end
    end
    return false
end

-- Accepted slot types come from the career's own table (a Slayer's ranged
-- slot accepts melee weapons) [src: career_settings.lua item_slot_types_by_slot_name;
-- playfab_mirror_base.lua:1708-1712].
local DEFAULT_SLOT_TYPES = {
    slot_melee = { "melee" }, slot_ranged = { "ranged" }, slot_necklace = { "necklace" },
    slot_ring = { "ring" }, slot_trinket_1 = { "trinket" }, slot_hat = { "hat" },
    slot_skin = { "skin" }, slot_frame = { "frame" }, slot_pose = { "weapon_pose" },
}

local function accepted_slot_types(settings, slot_name)
    local by_slot = type(settings) == "table" and settings.item_slot_types_by_slot_name or nil
    local accepted = type(by_slot) == "table" and by_slot[slot_name] or nil
    if type(accepted) == "table" and #accepted > 0 then return accepted end
    return DEFAULT_SLOT_TYPES[slot_name] or {}
end

local function accepts(accepted, slot_type)
    for _, name in ipairs(accepted) do
        if name == slot_type then return true end
    end
    return false
end

local function usable(data, career, accepted)
    if type(accepted) == "string" then accepted = { accepted } end
    return accepts(accepted, data.slot_type) and data.rarity ~= "magic" and wieldable(data, career)
end

local function reverse_deus_mapping(env)
    if env._reverse_deus then return env._reverse_deus end
    local reverse = {}
    if type(env.deus_mapping) == "table" then
        for adventure_key, deus_key in pairs(env.deus_mapping) do
            if type(adventure_key) == "string" and type(deus_key) == "string" then
                reverse[deus_key] = adventure_key
            end
        end
    end
    env._reverse_deus = reverse
    return reverse
end

-- Vanilla starting gear is granted server-side by the fixCareerData
-- CloudScript [src: playfab_mirror_base.lua:3292-3313] and is not in the
-- client tree. The client does ship one source-backed default loadout per
-- career: the Chaos Wastes starting weapons [src: deus_weapons.lua:1428-1508],
-- keyed back to adventure item keys through DeusStartingWeaponTypeMapping
-- [src: deus_weapons.lua:1510-1571].
local function pick_weapon(env, career, settings, slot_name)
    local accepted = accepted_slot_types(settings, slot_name)
    local defaults = type(env.deus_default_loadout) == "table" and env.deus_default_loadout[career] or nil
    local deus_key = type(defaults) == "table" and defaults[slot_name] or nil
    if deus_key then
        local key = reverse_deus_mapping(env)[deus_key]
        local data = item_data(env, key)
        if data and usable(data, career, accepted) then return key, "deus_default" end
    end
    local mapping = type(env.deus_mapping) == "table" and env.deus_mapping or nil
    for _, key in ipairs(sorted_keys(env.item_master_list)) do
        local data = item_data(env, key)
        if data and data.rarity == "plentiful" and usable(data, career, accepted)
                and (mapping == nil or mapping[key] ~= nil) then
            return key, "plentiful_fallback"
        end
    end
    return nil
end

local function pick_first(env, predicate)
    for _, key in ipairs(sorted_keys(env.item_master_list)) do
        local data = item_data(env, key)
        if data and predicate(key, data) then return key end
    end
    return nil
end

local function pick_jewellery(env, career, settings, slot_name)
    local accepted = accepted_slot_types(settings, slot_name)
    return pick_first(env, function(_, data)
        return data.rarity == "plentiful" and data.required_dlc == nil and usable(data, career, accepted)
    end)
end

-- Every career ships exactly one plentiful, career-specific default hat
-- (`<career>_hat_0000`) plus shared plentiful hats; prefer the single-career
-- row so the seed matches the vanilla default presentation.
local function pick_hat(env, career)
    local single = pick_first(env, function(_, data)
        return data.rarity == "plentiful" and usable(data, career, "hat")
            and type(data.can_wield) == "table" and #data.can_wield == 1
    end)
    if single then return single end
    return pick_first(env, function(_, data)
        return data.rarity == "plentiful" and usable(data, career, "hat")
    end)
end

-- [src: career_settings.lua base_skin per career]
local function pick_skin(env, career, settings)
    local base = type(settings) == "table" and settings.base_skin or nil
    local data = item_data(env, base)
    if data and usable(data, career, "skin") then return base end
    return pick_first(env, function(_, data)
        return data.rarity == "plentiful" and usable(data, career, "skin")
    end)
end

local function pick_frame(env, career)
    return pick_first(env, function(_, data)
        return data.rarity == "default" and usable(data, career, "frame")
    end)
end

function M.seed_items(profile, env)
    assert(type(profile) == "table" and is_index(profile.generation), "profile required")
    env = env or {}
    local careers = type(env.career_settings) == "table" and env.career_settings or {}
    local generation = profile.generation
    local prefix = M.ID_PREFIX .. "g" .. tostring(generation) .. "_"
    local power = tonumber(env.item_power_level) or 0
    local slice = {
        generation = generation,
        revision = 1,
        inventory = {},
        cosmetics = {},
        careers = {},
        pose_skins = {},
    }
    local report = { careers = 0, weapons = 0, jewellery = 0, cosmetics = 0, missing = 0, sources = {} }
    local cosmetic_ids = {}

    local function cosmetic_id(key)
        local id = cosmetic_ids[key]
        if not id then
            id = prefix .. "cos_" .. key
            cosmetic_ids[key] = id
            slice.cosmetics[id] = { ItemId = key, ItemInstanceId = id }
            report.cosmetics = report.cosmetics + 1
        end
        return id
    end

    -- Vanilla iterates CareerSettings rows that carry a playfab_name
    -- [src: backend_interface_item_playfab.lua:113-114].
    for _, career in ipairs(sorted_keys(careers)) do
        local settings = careers[career]
        if type(settings) == "table" and settings.playfab_name then
            report.careers = report.careers + 1
            local loadout = {}
            for slot_name in pairs(M.WEAPON_SLOTS) do
                local key, source = pick_weapon(env, career, settings, slot_name)
                if key then
                    local id = prefix .. career .. "_" .. slot_name
                    slice.inventory[id] = { ItemId = key, ItemInstanceId = id, power_level = power }
                    loadout[slot_name] = id
                    report.weapons = report.weapons + 1
                    report.sources[source] = (report.sources[source] or 0) + 1
                else
                    report.missing = report.missing + 1
                end
            end
            for slot_name in pairs(M.JEWELLERY_SLOTS) do
                local key = pick_jewellery(env, career, settings, slot_name)
                if key then
                    local id = prefix .. career .. "_" .. slot_name
                    slice.inventory[id] = { ItemId = key, ItemInstanceId = id, power_level = power }
                    loadout[slot_name] = id
                    report.jewellery = report.jewellery + 1
                else
                    report.missing = report.missing + 1
                end
            end
            local hat, skin, frame = pick_hat(env, career), pick_skin(env, career, settings), pick_frame(env, career)
            if hat then cosmetic_id(hat); loadout.slot_hat = hat else report.missing = report.missing + 1 end
            if skin then cosmetic_id(skin); loadout.slot_skin = skin else report.missing = report.missing + 1 end
            if frame then cosmetic_id(frame); loadout.slot_frame = frame else report.missing = report.missing + 1 end
            slice.careers[career] = { selected = 1, loadouts = { loadout } }
        end
    end
    return slice, report
end

-- ============================================================
-- Hydration: persisted slice -> runtime view shaped like the native interface
-- ============================================================
-- Native records carry backend_id/key/data/rarity and, for equipment,
-- decoded power/properties/traits [src: playfab_mirror_base.lua:1723-1787].
local function equipment_record(key, id, data, power_level)
    local rarity = data.rarity
    return {
        ItemId = key,
        ItemInstanceId = id,
        CustomData = { rarity = rarity, power_level = tostring(power_level) },
        backend_id = id,
        key = key,
        data = data,
        rarity = rarity,
        power_level = power_level,
        properties = {},
        traits = {},
    }
end

-- Native fake cosmetic rows are { ItemId, ItemInstanceId } run through
-- _update_data [src: playfab_mirror_base.lua:2337-2341,2398].
local function cosmetic_record(key, id, data)
    return {
        ItemId = key,
        ItemInstanceId = id,
        backend_id = id,
        key = key,
        data = data,
        rarity = data.rarity,
    }
end

local function add_cosmetic(view, key, id, data)
    if view.unlocked_cosmetics[key] then return false end
    local record = cosmetic_record(key, id, data)
    view.items[id] = record
    view.fake_items[id] = record
    view.unlocked_cosmetics[key] = id
    return true
end

local function track_power(view, data, power_level)
    local slot_type = data.slot_type
    if not M.EQUIPMENT_SLOT_TYPES[slot_type] or type(power_level) ~= "number" then return end
    local best = view.best_power[slot_type]
    if not best or power_level > best then view.best_power[slot_type] = power_level end
end

function M.hydrate(slice, env, extras)
    assert(type(slice) == "table", "slice required")
    env = env or {}
    extras = extras or {}
    local view = {
        generation = slice.generation,
        revision = slice.revision,
        extras_revision = extras.revision,
        items = {},
        fake_items = {},
        unlocked_cosmetics = {},
        unlocked_weapon_skins = {},
        unlocked_weapon_poses = {},
        careers = slice.careers,
        pose_skins = type(slice.pose_skins) == "table" and slice.pose_skins or {},
        best_power = {},
        dropped = 0,
    }
    for _, id in ipairs(sorted_keys(slice.inventory)) do
        local rec = slice.inventory[id]
        local data = type(rec) == "table" and item_data(env, rec.ItemId) or nil
        if data then
            local power = tonumber(rec.power_level) or 0
            view.items[id] = equipment_record(rec.ItemId, id, data, power)
            track_power(view, data, power)
        else
            view.dropped = view.dropped + 1
        end
    end
    for _, id in ipairs(sorted_keys(slice.cosmetics)) do
        local rec = slice.cosmetics[id]
        local data = type(rec) == "table" and item_data(env, rec.ItemId) or nil
        if data then
            add_cosmetic(view, rec.ItemId, id, data)
        else
            view.dropped = view.dropped + 1
        end
    end
    -- Durable Emporium grants (#577) are part of the MP profile, not the
    -- official mirror, so the Fresh view carries them instead of overlaying
    -- the native mirror.
    local classify = type(extras.classify) == "function" and extras.classify or nil
    for _, id in ipairs(sorted_keys(extras.emporium)) do
        local item = extras.emporium[id]
        local key = type(item) == "table" and item.ItemId or nil
        local data = item_data(env, key)
        local kind = data and classify and classify(key, data) or nil
        if kind == "cosmetic" then
            add_cosmetic(view, key, id, data)
        elseif kind == "weapon_pose" and type(data.parent) == "string" then
            local record = cosmetic_record(key, id, data)
            view.items[id] = record
            view.fake_items[id] = record
            view.unlocked_weapon_poses[data.parent] = view.unlocked_weapon_poses[data.parent] or {}
            view.unlocked_weapon_poses[data.parent][key] = id
        elseif kind == "weapon_skin" then
            local weapon_key = type(extras.skin_item_key) == "function" and extras.skin_item_key(key) or nil
            local weapon_data = item_data(env, weapon_key)
            if weapon_data and not view.unlocked_weapon_skins[key] then
                local record = cosmetic_record(weapon_key, id, weapon_data)
                record.CustomData = { skin = key, rarity = data.rarity }
                record.skin = key
                record.rarity = data.rarity or weapon_data.rarity
                view.items[id] = record
                view.fake_items[id] = record
                view.unlocked_weapon_skins[key] = id
            else
                view.dropped = view.dropped + 1
            end
        elseif kind == "item" then
            local power = tonumber(item.power_level)
                or tonumber(type(item.CustomData) == "table" and item.CustomData.power_level) or 0
            view.items[id] = equipment_record(key, id, data, power)
            track_power(view, data, power)
        elseif key ~= nil then
            view.dropped = view.dropped + 1
        end
    end
    return view
end

function M.sum_best_power_levels(view)
    local total = 0
    for _, power in pairs(view.best_power or {}) do total = total + power end
    return total
end

-- ============================================================
-- Loadout reads
-- ============================================================
local function career_state(view_or_slice, career)
    local careers = view_or_slice and view_or_slice.careers
    local state = type(careers) == "table" and careers[career] or nil
    if type(state) ~= "table" or type(state.loadouts) ~= "table" then return nil end
    return state
end

local function selected_loadout(state)
    local index = is_index(state.selected) and state.selected or 1
    return state.loadouts[index] or state.loadouts[1], index
end

function M.loadouts(view)
    local result = {}
    for career, state in pairs(view.careers or {}) do
        if type(state) == "table" and type(state.loadouts) == "table" then
            result[career] = deep_copy((selected_loadout(state)))
        end
    end
    return result
end

function M.career_loadout(view, career)
    local state = career_state(view, career)
    if not state then return nil end
    return deep_copy((selected_loadout(state)))
end

function M.career_loadouts(view, career)
    local state = career_state(view, career)
    if not state then return nil end
    local result = {}
    for index, loadout in ipairs(state.loadouts) do result[index] = deep_copy(loadout) end
    return result
end

function M.selected_index(view, career)
    local state = career_state(view, career)
    if not state then return nil end
    local _, index = selected_loadout(state)
    return index
end

-- Mirrors the native bot loadout resolution: a bot uses the custom loadout
-- chosen for it when that loadout exists, else the player's selected one
-- [src: backend_interface_item_playfab.lua:128-160].
function M.bot_loadouts(view, bot_equipment, allowed)
    local result = M.loadouts(view)
    if not allowed or type(bot_equipment) ~= "table" then return result end
    for career, index in pairs(bot_equipment) do
        local state = career_state(view, career)
        if state and is_index(index) and state.loadouts[index] then
            result[career] = deep_copy(state.loadouts[index])
        end
    end
    return result
end

-- The id the seed minted for a career's equipment slot (M.seed_items), when
-- the view still resolves it. Weapon and jewellery slots share this shape.
function M.default_equipment_id(view, career, slot_name)
    if type(view) ~= "table" or type(view.items) ~= "table" then return nil end
    local id = M.ID_PREFIX .. "g" .. tostring(view.generation) .. "_" .. tostring(career) .. "_" .. tostring(slot_name)
    return view.items[id] ~= nil and id or nil
end

-- [src: backend_interface_item_playfab.lua:512-538]
-- Returns the backend id plus a fallback reason. Vanilla's spawn consumer
-- resolves the id through `get_item_from_id` and ferrors when the default
-- wielded slot stays empty [src: simple_inventory_extension.lua:162-174,
-- 375-425], so an equipment slot never answers an id the same view cannot
-- resolve: it falls back to the seeded career default, else nil.
function M.loadout_item_id(view, career, slot_name, opts)
    opts = opts or {}
    local base = M.career_loadout(view, career)
    local loadout = base
    if opts.is_bot and opts.bot_allowed and type(opts.bot_loadout) == "table" and next(opts.bot_loadout) then
        loadout = opts.bot_loadout
    end
    local item_id = loadout and loadout[slot_name]
    if item_id == nil then return nil end
    if M.COSMETIC_SLOTS[slot_name] then
        return view.unlocked_cosmetics[item_id]
    elseif slot_name == "slot_pose" then
        local data = item_data(opts.env or {}, item_id)
        local parent = data and data.parent
        local poses = parent and view.unlocked_weapon_poses[parent]
        return poses and poses[item_id]
    end
    if view.items[item_id] ~= nil then return item_id end
    local default_id = M.default_equipment_id(view, career, slot_name)
    if default_id then return default_id, "unresolved:" .. tostring(item_id) end
    return nil, "unresolved:" .. tostring(item_id)
end

-- [src: backend_interface_item_playfab.lua:760-800]
function M.equipped_by_loadout(view, backend_id)
    local result = {}
    for career, state in pairs(view.careers or {}) do
        if type(state) == "table" and type(state.loadouts) == "table" then
            for index, loadout in ipairs(state.loadouts) do
                for _, item_id in pairs(loadout) do
                    if item_id == backend_id then
                        result[career] = result[career] or {}
                        result[career][#result[career] + 1] = index
                    end
                end
            end
            if result[career] then result[career].num_loadouts = #state.loadouts end
        end
    end
    return result
end

function M.is_equipped_by_any_loadout(view, backend_id)
    local result = {}
    for _, career in ipairs(sorted_keys(view.careers)) do
        local state = view.careers[career]
        if type(state) == "table" and type(state.loadouts) == "table" then
            for index, loadout in ipairs(state.loadouts) do
                for _, item_id in pairs(loadout) do
                    if item_id == backend_id then result[#result + 1] = career .. "_" .. index end
                end
            end
        end
    end
    return result
end

-- ============================================================
-- Loadout writes (mutate a slice copy; the runtime persists and swaps)
-- ============================================================
local function bump(slice)
    slice.revision = (is_index(slice.revision) and slice.revision or 0) + 1
end

function M.set_loadout_item(slice, career, slot_name, value, optional_index)
    local state = career_state(slice, career)
    if not state then return false, "career_unknown" end
    local loadout, selected = selected_loadout(state)
    local index = optional_index or selected
    local target = is_index(index) and state.loadouts[index] or nil
    if not target then return false, "loadout_unknown" end
    local known = false
    for _, slot in ipairs(M.LOADOUT_SLOTS) do
        if slot == slot_name then known = true end
    end
    if not known then return false, "slot_unknown" end
    target[slot_name] = value
    bump(slice)
    return true, loadout
end

-- [src: playfab_mirror_base.lua:1968-1992]
function M.set_loadout_index(slice, career, index)
    local state = career_state(slice, career)
    if not state or not is_index(index) or not state.loadouts[index] then return false, "loadout_unknown" end
    state.selected = index
    bump(slice)
    return true
end

-- [src: playfab_mirror_base.lua:2036-2068]
function M.add_loadout(slice, career, max_loadouts)
    local state = career_state(slice, career)
    if not state then return false, "career_unknown" end
    local current, selected = selected_loadout(state)
    local limit = tonumber(max_loadouts) or 0
    if #state.loadouts >= limit then return false, "loadout_limit" end
    state.loadouts[#state.loadouts + 1] = deep_copy(current or {})
    state.selected = math.min(selected + 1, #state.loadouts)
    bump(slice)
    return true
end

-- [src: playfab_mirror_base.lua:1994-2034]
function M.delete_loadout(slice, career, index)
    local state = career_state(slice, career)
    if not state or not is_index(index) then return false, "loadout_unknown" end
    local loadouts = state.loadouts
    if index > #loadouts or #loadouts == 1 then return false, "loadout_protected" end
    local _, selected = selected_loadout(state)
    table.remove(loadouts, index)
    if index == selected then
        state.selected = 1
    else
        state.selected = math.max(1, math.min(selected, #loadouts))
    end
    bump(slice)
    return true
end

-- [src: playfab_mirror_base.lua:2253-2255]
function M.set_weapon_pose_skin(slice, parent_item_name, skin_name)
    if type(parent_item_name) ~= "string" then return false, "parent_unknown" end
    slice.pose_skins = type(slice.pose_skins) == "table" and slice.pose_skins or {}
    slice.pose_skins[parent_item_name] = skin_name
    bump(slice)
    return true
end

function M.summary(slice)
    if type(slice) ~= "table" then return "unseeded" end
    return string.format("generation=%s revision=%s inventory=%d cosmetics=%d careers=%d",
        tostring(slice.generation), tostring(slice.revision),
        count(slice.inventory), count(slice.cosmetics), count(slice.careers))
end

return M
