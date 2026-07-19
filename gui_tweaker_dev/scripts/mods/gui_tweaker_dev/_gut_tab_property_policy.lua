-- Pure refresh policy for the held-Tab loadout cache - the engine-free half of
-- the single live-session Tab provider (#245 properties/traits, #246 equipped
-- illusion, #533 Chaos Wastes collectible rows; #250's tier policy stays in
-- _gut_tab_talent_policy.lua). Offline-tested via qa/lua/tests.
local Policy = { INTERVAL = 0.25, MAX_LOGS = 16 }

local function clone(values)
    if type(values) ~= "table" then return nil end
    local out = {}
    for key, value in pairs(values) do out[key] = value end
    return out
end

local function instance_id(item)
    return item and (item.backend_id or item.backendId or item.id)
end

function Policy.fingerprint(values)
    if type(values) ~= "table" then return "-" end
    local parts = {}
    for key, value in pairs(values) do
        parts[#parts + 1] = tostring(key) .. "=" .. tostring(value)
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

-- Shared identity gate for every per-slot refresh: the cached snapshot and the
-- live backend item must describe the SAME weapon key and (when both carry one)
-- the same backend instance, or the cache is preserved untouched.
local function identity_matches(cached_item, live_item)
    if type(cached_item) ~= "table" or type(live_item) ~= "table" then
        return false, "missing_item"
    end
    local cached_key = cached_item.key or cached_item.ItemId
        or cached_item.data and (cached_item.data.key or cached_item.data.name)
    local live_key = live_item.key or live_item.ItemId
        or live_item.data and (live_item.data.key or live_item.data.name)
    if not cached_key or cached_key ~= live_key then
        return false, "identity_mismatch"
    end
    local cached_id, live_id = instance_id(cached_item), instance_id(live_item)
    if cached_id ~= nil and live_id ~= nil and tostring(cached_id) ~= tostring(live_id) then
        return false, "instance_mismatch"
    end
    return true, nil
end

function Policy.refresh(cached_item, live_item)
    local ok, reason = identity_matches(cached_item, live_item)
    if not ok then
        return false, nil, reason
    end
    if Policy.fingerprint(cached_item.properties) == Policy.fingerprint(live_item.properties) then
        return false, nil, "unchanged"
    end
    return true, clone(live_item.properties), "changed"
end

-- #245 also covers TRAITS: a reforge re-rolls the trait alongside properties.
-- Traits are an ARRAY of trait names (loadout_utils.lua:105-113 wire shape).
local function traits_fingerprint(traits)
    if type(traits) ~= "table" then return "-" end
    local parts = {}
    for i = 1, #traits do parts[#parts + 1] = tostring(traits[i]) end
    return table.concat(parts, ";")
end

Policy.traits_fingerprint = traits_fingerprint

function Policy.refresh_traits(cached_item, live_item)
    local ok, reason = identity_matches(cached_item, live_item)
    if not ok then
        return false, nil, reason
    end
    if traits_fingerprint(cached_item.traits) == traits_fingerprint(live_item.traits) then
        return false, nil, "unchanged"
    end
    local out = {}
    local live_traits = live_item.traits
    if type(live_traits) == "table" then
        for i = 1, #live_traits do out[i] = live_traits[i] end
    end
    return true, out, "changed"
end

-- Wire-safety filters (belt-and-suspenders): the cached loadout row can be
-- re-serialized by vanilla's hot-join resync (LoadoutUtils.hot_join_sync ->
-- properties_to_rpc_params, loadout_utils.lua:47-68/90-116), where a name
-- missing from NetworkLookup would leave nil holes in the RPC arrays and trip
-- the sender fassert (loadout_utils.lua:29-31). Vanilla itself cannot equip
-- such an item without hitting the same fassert at add_equipment, so in
-- practice these filters drop nothing - but a silent skip beats a host crash.
-- lookup == nil (offline tests, boot order) filters nothing.
function Policy.wire_safe_properties(properties, lookup)
    if type(properties) ~= "table" then return nil, 0 end
    if type(lookup) ~= "table" then return properties, 0 end
    local out, dropped = {}, 0
    for name, value in pairs(properties) do
        if lookup[name] ~= nil then
            out[name] = value
        else
            dropped = dropped + 1
        end
    end
    return out, dropped
end

function Policy.wire_safe_traits(traits, lookup)
    if type(traits) ~= "table" then return nil, 0 end
    if type(lookup) ~= "table" then return traits, 0 end
    local out, dropped = {}, 0
    for i = 1, #traits do
        if lookup[traits[i]] ~= nil then
            out[#out + 1] = traits[i]
        else
            dropped = dropped + 1
        end
    end
    return out, dropped
end

-- #246 equipped-illusion resolution chain, per docs/WEAPON_APPEARANCE_STANDARD
-- section 2: the Hold-Tab snapshot has no backend instance ID, so a row may be
-- decorated ONLY from (a) the exact live backend instance (available for the
-- LOCAL player's own slots) or (b) the explicitly synchronized (wearer, slot)
-- presentation identity (CosmeticUtils sync data, available for every player).
-- Absent or unresolvable evidence preserves the reconstructed vanilla
-- presentation. `known` flags distinguish "no evidence" from "evidence says no
-- illusion" - the latter must CLEAR a previously decorated skin.
-- skin_exists(name) must confirm the skin template is locally resident; the
-- vanilla icon pass dereferences WeaponSkins.skins[skin].inventory_icon
-- unguarded (ui_utils.lua:238-245), so writing an unresolvable name would
-- crash the panel draw.
function Policy.resolve_skin(live_known, live_skin, synced_known, synced_skin, current_skin, skin_exists)
    local pick, source
    if live_known then
        pick, source = live_skin, "live_backend"
    elseif synced_known then
        pick, source = synced_skin, "synced_cosmetic"
    else
        return current_skin, "preserved", false
    end
    if pick ~= nil and skin_exists and not skin_exists(pick) then
        return current_skin, "unresolved_template", false
    end
    if pick == current_skin then
        return current_skin, source, false
    end
    return pick, source, true
end

-- #533: the tome/grimoire/loot-die rows are ADVENTURE loot objectives (the
-- panel builds them from level_settings.loot_objectives against the
-- tome_bonus_mission/grimoire_hidden_mission/bonus_dice_hidden_mission
-- mission-system rows, ingame_player_list_ui_v2.lua:11-33/436-514). Inside the
-- deus mechanism (Chaos Wastes, including ct's injected adventure maps) those
-- missions do not track the run's collectibles (pilgrim coins / chests), so
-- the rows are misleading and are suppressed. The panel itself branches on the
-- same mechanism name for its CW node info (ingame_player_list_ui_v2.lua:
-- 292-309).
function Policy.suppress_adventure_loot_rows(mechanism_name)
    return mechanism_name == "deus"
end

return Policy
