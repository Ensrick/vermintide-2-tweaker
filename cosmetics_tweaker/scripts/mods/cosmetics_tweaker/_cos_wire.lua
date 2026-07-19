-- _cos_wire.lua -- custom weapon-skin wire-safety senders.
--
-- Owns the issue #421 null-and-restore boundary around every vanilla
-- rpc_add_equipment sender that reads a live equipment skin. Custom illusion
-- keys are never allowed onto vanilla's strict NetworkLookup wire; the local
-- slot is restored immediately after the vanilla continuation returns. This
-- coercion is unconditional and must never be gated by a setting.
--
-- Owned by: cosmetics_tweaker.lua entry point. `mod:dofile` does not inject a
-- file-global `mod`, so this module returns an installer and receives the owner
-- explicitly after _cos_illusions has populated owner._cos.custom_skin_keys.

local M = {}
local _unknown_weapon_skin_ids = {}

-- v0.9.75-dev: pure wrapper around the shipped sender boundary so the runtime
-- regression suite can drive the exact null-and-restore path without a network
-- session. Preserve up to four vanilla return values.
local function _wire_null_custom_skins(custom_skin_keys, slots, send_fn, context)
    local saved
    for _, slot_data in pairs(slots) do
        local skin = slot_data and slot_data.skin
        if skin and custom_skin_keys[skin] then
            saved = saved or {}
            saved[slot_data] = skin
            slot_data.skin = nil
            pcall(printf, "[cos:421] wire skin null (%s): %s -> n/a",
                tostring(context or "?"), tostring(skin))
        end
    end
    local r1, r2, r3, r4 = send_fn()
    if saved then
        for slot_data, skin in pairs(saved) do
            slot_data.skin = skin
        end
    end
    return r1, r2, r3, r4
end

local function _safe_get_weapon_skin_name(slot, optional_skin_id, decode_fn)
    local cosmetic_utils = CosmeticUtils
    if not (cosmetic_utils and type(cosmetic_utils.is_weapon_slot) == "function"
        and cosmetic_utils.is_weapon_slot(slot))
    then
        return decode_fn()
    end

    local skin_id = optional_skin_id or 1
    local network_lookup = NetworkLookup
    local weapon_skins = network_lookup and network_lookup.weapon_skins

    if type(weapon_skins) ~= "table" then
        return nil
    end

    local skin_name = rawget(weapon_skins, skin_id)
    if skin_name == nil then
        local key = tostring(slot) .. "|" .. tostring(skin_id)
        if not _unknown_weapon_skin_ids[key] then
            _unknown_weapon_skin_ids[key] = true
            pcall(printf, "[cos:734] wire skin decode fallback (%s): unknown weapon_skins id=%s -> n/a",
                tostring(slot), tostring(skin_id))
        end
        return nil
    end

    return decode_fn()
end

function M.install(owner)
    assert(type(owner) == "table", "_cos_wire.install requires the owning mod")
    assert(type(owner._cos) == "table", "_cos_wire.install requires owner._cos")
    local custom_skin_keys = owner._cos.custom_skin_keys
    assert(type(custom_skin_keys) == "table",
        "_cos_wire.install requires owner._cos.custom_skin_keys")
    assert(type(owner.hook) == "function", "_cos_wire.install requires owner:hook")

    -- Hot reloads must not stack another copy of each sender hook.
    if owner._cos_wire_installed then
        return true
    end

    local function null_custom_skins(slots, send_fn, context)
        return _wire_null_custom_skins(custom_skin_keys, slots, send_fn, context)
    end

    -- These established mod fields are frozen regression/documentation surface.
    owner._cos_wire_null_custom_skins = null_custom_skins
    owner._cos_wire_safe_get_weapon_skin_name = _safe_get_weapon_skin_name
    owner._cos_skin_wire_surfaces = {}

    -- Initial player equipment broadcast.
    owner:hook("SimpleInventoryExtension", "game_object_initialized", function(func, self, unit, unit_go_id)
        local slots = self and self._equipment and self._equipment.slots
        if not slots then
            return func(self, unit, unit_go_id)
        end
        return null_custom_skins(slots, function()
            return func(self, unit, unit_go_id)
        end, "game_object_initialized")
    end)
    owner._cos_skin_wire_surfaces.game_object_initialized = true

    -- Mid-session equip/loadout respawn broadcast. equipment_to_spawn is one
    -- slot-shaped table, so wrap it for the shared pairs() traversal.
    owner:hook("SimpleInventoryExtension", "_spawn_resynced_loadout", function(func, self, equipment_to_spawn, skip_wield)
        if not (equipment_to_spawn and equipment_to_spawn.skin) then
            return func(self, equipment_to_spawn, skip_wield)
        end
        return null_custom_skins({ equipment_to_spawn }, function()
            return func(self, equipment_to_spawn, skip_wield)
        end, "spawn_resynced_loadout")
    end)
    owner._cos_skin_wire_surfaces.spawn_resynced_loadout = true

    -- Host replay to a joining peer.
    owner:hook("GearUtils", "hot_join_sync", function(func, peer_id, unit, equipment, additional_items)
        local slots = equipment and equipment.slots
        if not slots then
            return func(peer_id, unit, equipment, additional_items)
        end
        return null_custom_skins(slots, function()
            return func(peer_id, unit, equipment, additional_items)
        end, "hot_join_sync")
    end)
    owner._cos_skin_wire_surfaces.hot_join_sync = true

    -- Issue #734 receiver floor: session-score/player-list readers eventually
    -- decode slot.."_skin" through CosmeticUtils.get_weapon_skin_name. The
    -- vanilla helper strict-indexes NetworkLookup.weapon_skins[skin_id], so a
    -- modded numeric id from another peer/version can CTD this client before any
    -- appearance fallback runs. Use rawget first and degrade an unknown weapon
    -- skin id to no-skin. Sender-side substitution remains the real fix; this is
    -- a generic crash floor for the score/profile-sync read path.
    local cosmetic_utils = CosmeticUtils
    if cosmetic_utils and type(cosmetic_utils.get_weapon_skin_name) == "function" then
        owner:hook(cosmetic_utils, "get_weapon_skin_name", function(func, slot, optional_skin_id)
            return _safe_get_weapon_skin_name(slot, optional_skin_id, function()
                return func(slot, optional_skin_id)
            end)
        end)
        owner._cos_skin_wire_surfaces.get_weapon_skin_name = true
    end

    owner._cos_wire_installed = true
    return true
end

return M
