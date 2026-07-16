-- _cim_synthetic_item_contract.lua -- canonical CIM-owned item policy.
--
-- A crafted mod weapon is one identity shared by every CIM surface. Provider
-- mods own ItemMasterList definitions; CIM owns acquired backend instances and
-- their persistence. This engine-free module normalizes that boundary once,
-- validates provider rows before a UI consumes them, builds the one mirror
-- payload shape, and applies vanilla-compatible salvage safety rules.

local M = {}

M.SCHEMA_VERSION = 1
M.OWNER = "cim"

local SALVAGE_SLOTS = {
    melee = true,
    ranged = true,
    ring = true,
    necklace = true,
    trinket = true,
}

local UNSALVAGEABLE_RARITIES = {
    default = true,
    promo = true,
    magic = true,
}

local function copy_map(value)
    local result = {}
    if type(value) == "table" then
        for key, child in pairs(value) do result[key] = child end
    end
    return result
end

local function copy_array(value)
    local result = {}
    if type(value) == "table" then
        for i = 1, #value do result[i] = value[i] end
    end
    return result
end

local function nonempty_array(value)
    return type(value) == "table" and #value > 0
end

function M.provider_for(item_key, master)
    if type(master) == "table" then
        if master.cwv_variant == true or master.cwv_definition == true
                or type(master.cwv_key) == "string" then
            return "cwv"
        end
        if master.woc_variant == true then return "woc" end
    end
    if type(item_key) == "string" then
        if item_key:sub(1, 4) == "cwv_" then return "cwv" end
        if item_key:sub(1, 4) == "woc_" then return "woc" end
    end
    return "vanilla"
end

function M.is_immutable_relic(item)
    if type(item) ~= "table" then return false end
    if item.woc_unique_relic == true then return true end
    if type(item.data) == "table" and item.data.woc_unique_relic == true then return true end
    local custom = item.CustomData
    return type(custom) == "table"
        and (custom.woc_unique_relic == true or custom.woc_unique_relic == "true")
end

-- Returns true for ordinary vanilla rows (they remain vanilla-owned), or for a
-- complete provider row. A malformed mod-provider definition returns false and
-- a bounded problem list so acquisition selectors can reject it before draw.
function M.validate_provider(item_key, master)
    local provider = M.provider_for(item_key, master)
    if provider == "vanilla" then return true, {}, provider end

    -- WOC trophy weapons are deterministic one-per-account local relics.  The
    -- provider marker is the sole cross-mod boundary: no CIM acquisition path
    -- may turn one into a second crafted/editable instance.
    if M.is_immutable_relic(master) then
        return false, { "immutable_relic" }, provider
    end

    local problems = {}
    if type(item_key) ~= "string" or item_key == "" then
        problems[#problems + 1] = "item_key"
    end
    if type(master) ~= "table" then
        problems[#problems + 1] = "master"
        return false, problems, provider
    end
    if not SALVAGE_SLOTS[master.slot_type] then
        problems[#problems + 1] = "slot_type"
    end
    if not nonempty_array(master.can_wield) then
        problems[#problems + 1] = "can_wield"
    end
    if type(master.template) ~= "string" or master.template == "" then
        problems[#problems + 1] = "template"
    end
    if type(master.item_type) ~= "string" or master.item_type == "" then
        problems[#problems + 1] = "item_type"
    end
    if type(master.inventory_icon) ~= "string" or master.inventory_icon == "" then
        problems[#problems + 1] = "inventory_icon"
    end

    return #problems == 0, problems, provider
end

function M.normalize_record(backend_id, input, master)
    if type(backend_id) ~= "string" or backend_id == "" then
        return nil, "backend_id"
    end
    if type(input) ~= "table" then return nil, "record" end

    local item_key = input.item_key or input.ItemId or input.key
    if type(item_key) ~= "string" or item_key == "" then
        return nil, "item_key"
    end

    if master ~= nil then
        local ok, problems = M.validate_provider(item_key, master)
        if not ok then return nil, "provider:" .. table.concat(problems, ",") end
    end

    local rarity = input.rarity
    if rarity == nil or rarity == "promo" then rarity = "modded" end

    local traits = input.traits
    if type(traits) ~= "table" then
        traits = input.trait and { input.trait } or {}
    end

    return {
        schema_version = M.SCHEMA_VERSION,
        owner = M.OWNER,
        backend_id = backend_id,
        item_key = item_key,
        provider = M.provider_for(item_key, master),
        slot_type = type(master) == "table" and master.slot_type or input.slot_type,
        properties = copy_map(input.properties),
        trait = input.trait,
        traits = copy_array(traits),
        skin = input.skin,
        power_level = tonumber(input.power_level) or 300,
        rarity = rarity,
        via_mirror = input.via_mirror ~= false,
        rerolled_props_indices = copy_array(input.rerolled_props_indices),
        rerolled_trait_indices = copy_array(input.rerolled_trait_indices),
        custom_glow = input.custom_glow,
    }
end

function M.build_mirror_payload(record, master, json_encode)
    if type(record) ~= "table" then return nil, "record" end
    local normalized, err = M.normalize_record(record.backend_id, record, master)
    if not normalized then return nil, err end

    local custom_data = {
        power_level = tostring(normalized.power_level),
        rarity = normalized.rarity,
    }
    if type(json_encode) == "function" then
        custom_data.properties = json_encode(normalized.properties)
        custom_data.traits = json_encode(normalized.traits)
    end
    if normalized.skin then custom_data.skin = normalized.skin end

    return {
        ItemId = normalized.item_key,
        ItemInstanceId = normalized.backend_id,
        CustomData = custom_data,
    }, nil, normalized
end

-- issue 628: the ONE canonical identity for a synthetic item, owned here and
-- consumed by every CIM surface (salvage eligibility below AND the standard-forge
-- acquisition selector via `_cim_template_selector.set_canonical_key_resolver`).
-- Before this, the salvage path resolved identity as `ItemId or key or cwv_key`
-- while the craft selector used a cwv_key-first, backend-id-aware resolver. They
-- disagreed for any CWV row presented with its inherited BASE `.key`/`.name`
-- (CWV's `_build_entry` deliberately keeps them the base weapon for vanilla
-- equip/preview fallbacks and stamps the variant only on `.cwv_key`,
-- character_weapon_variants.lua:10318-10330). A variant-keyed salvage record then
-- failed the `item_key` check and the crafted weapon never appeared in Salvage.
-- Resolution priority (highest first):
--   1. `cim_acquisition_key` -- the exact craft key on a synthetic selector row.
--   2. `data.cwv_key` -- the self-identifying variant marker.
--   3. `cwv_<key>_NNN` backend-id band -- legacy CWV blacksmith instances that
--      encoded the variant only in the backend id.
--   4. `ItemId` / `key` / `data.key` -- ordinary vanilla identity.
function M.canonical_item_key(item)
    if type(item) ~= "table" then return nil end
    if type(item.cim_acquisition_key) == "string" then
        return item.cim_acquisition_key
    end
    local data = type(item.data) == "table" and item.data or nil
    if data and type(data.cwv_key) == "string" then
        return data.cwv_key
    end
    local backend_id = item.backend_id or item.ItemInstanceId
    if type(backend_id) == "string" then
        local cwv_key = backend_id:match("^(cwv_.-)_%d%d%d$")
        if cwv_key then return cwv_key end
    end
    local key = item.ItemId or item.key or (data and data.key)
    return type(key) == "string" and key or nil
end

local function instance_key(item)
    return item and M.canonical_item_key(item)
end

function M.validate_instance(item, record)
    if type(item) ~= "table" or type(record) ~= "table" then
        return false, "not_owned"
    end
    local backend_id = item.backend_id or item.ItemInstanceId
    if backend_id ~= record.backend_id then return false, "backend_id" end
    if record.owner ~= M.OWNER or record.schema_version ~= M.SCHEMA_VERSION then
        return false, "schema"
    end
    if instance_key(item) ~= record.item_key then return false, "item_key" end
    local slot_type = item.data and item.data.slot_type or record.slot_type
    if not SALVAGE_SLOTS[slot_type] then return false, "slot_type" end
    return true
end

-- `state` is deliberately explicit and engine-free. Runtime callers source it
-- from the same vanilla item interface / ItemHelper checks used by
-- BackendInterfaceCommon.can_salvage; offline tests exhaust the truth table.
function M.is_salvage_eligible(item, record, state)
    local valid, reason = M.validate_instance(item, record)
    if not valid then return false, reason end
    state = state or {}
    local rarity = item.rarity or record.rarity
    if UNSALVAGEABLE_RARITIES[rarity] then return false, "rarity" end
    if state.is_equipped then return false, "equipped" end
    if state.is_equipped_by_any_loadout then return false, "loadout" end
    if state.is_favorite then return false, "favorite" end
    return true
end

function M.partition_exact_ids(ids, records)
    local owned, foreign, seen = {}, {}, {}
    for i = 1, #(ids or {}) do
        local backend_id = ids[i]
        if type(backend_id) == "string" and not seen[backend_id] then
            seen[backend_id] = true
            if type(records) == "table" and records[backend_id] then
                owned[#owned + 1] = backend_id
            else
                foreign[#foreign + 1] = backend_id
            end
        end
    end
    return owned, foreign
end

return M
