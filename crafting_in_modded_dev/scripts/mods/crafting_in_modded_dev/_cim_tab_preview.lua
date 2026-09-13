-- Hold-Tab player weapon icon / owner-only rarity correction (#246/#598).
--
-- Vanilla's player-list loadout is reconstructed by rpc_sync_loadout_slot,
-- whose payload omits weapon-skin identity. The live inventory extension is
-- authoritative here: rpc_add_equipment carries weapon_skin_id and stores the
-- decoded key in equipment.slots[slot].skin. Reconcile those two already-local
-- views after the player list refreshes; no new RPC or network value is needed.

local mod = get_mod("cim_dev")
local Core = mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_tab_preview_core")
local WEAPON_SLOTS = { "slot_melee", "slot_ranged" }
local reported_unknown_skins = {}
local owner_frames = setmetatable({}, { __mode = "k" })
local owner_frame_budget = 24

local function _player_loadouts(manager)
    return manager:player_loadouts()
end

local function _player_context(player)
    local unit = player and player.player_unit
    local inventory = unit and ALIVE and ALIVE[unit]
        and ScriptUnit and ScriptUnit.has_extension(unit, "inventory_system")
    return inventory and inventory:equipment(), player and player:unique_id(), inventory
end

local function _local_cursed_texture(manager, player, equipment, inventory, slot_name)
    -- A remote/bot flag is not ownership. PlayerManager.local_player and owner
    -- prove the current local human/unit (player_manager.lua:341,580); a missing
    -- respawn association is intentionally unready, not a guessed local row.
    if not player or player.bot_player or player.local_player ~= true
            or manager:local_player() ~= player
            or not player.player_unit or not (ALIVE and ALIVE[player.player_unit])
            or manager:owner(player.player_unit) ~= player then
        return nil, "not-current-local-human"
    end
    local woc = get_mod("WOC")
    if not woc or type(woc.is_enabled) ~= "function" or woc:is_enabled() ~= true then
        return nil, "provider-unavailable"
    end
    local slot = equipment and equipment.slots and equipment.slots[slot_name]
    local item_data = slot and slot.item_data
    local backend_id = type(item_data) == "table" and rawget(item_data, "backend_id")
    if type(backend_id) ~= "string" or backend_id == "" then
        return nil, "exact-instance-unavailable"
    end
    local backend = Managers and Managers.backend
    if not backend then return nil, "backend-unavailable" end
    local owner = backend:get_loadout_interface_by_slot(slot_name)
    local items = backend:get_interface("items")
    -- BackendUtils.get_loadout_item always reads the items interface even when
    -- another interface owns this slot (backend_utils.lua:30-46). Do not use
    -- that cross-owner lookup for presentation: class 73 / #273. This bounded
    -- Adventure slice is inert for Deus/Weaves/unknown owners.
    if not owner or owner ~= items then return nil, "foreign-slot-owner" end
    local career = inventory and inventory._career_name
    if type(career) ~= "string" or career == ""
            or owner:get_loadout_item_id(career, slot_name, false) ~= backend_id then
        return nil, "equipped-instance-mismatch"
    end
    local item = owner:get_item_from_id(backend_id)
    local textures = UISettings and UISettings.item_rarity_textures
    local texture = Core.owner_cursed_texture(item, backend_id, textures,
        UIAtlasHelper and UIAtlasHelper.has_texture_by_name)
    return texture, texture and "exact-owner-cursed" or "rarity-or-resource-unavailable", backend_id
end

local function _apply_local_cursed_frame(manager, player, equipment, inventory, slot_name, content)
    -- The existing post-hook has already run vanilla and CIM's wire policy.
    -- A failed local lookup removes only our prior widget override; it cannot
    -- suppress a vanilla mutation or write a guessed item into shared state.
    local ok, texture, reason, backend_id = pcall(_local_cursed_texture,
        manager, player, equipment, inventory, slot_name)
    if not ok then texture, reason = nil, "owner-context-unavailable" end
    local previous = owner_frames[content]
    if texture then
        previous = previous or {}
        owner_frames[content] = previous
        Core.apply_owner_frame(content, slot_name, texture, previous)
    end
    if previous and owner_frame_budget > 0
            and (previous[slot_name .. "_reason"] ~= reason
                or previous[slot_name .. "_id"] ~= backend_id) then
        previous[slot_name .. "_reason"] = reason
        previous[slot_name .. "_id"] = backend_id
        owner_frame_budget = owner_frame_budget - 1
        pcall(printf, "[cim:598] owner_frame slot=%s reason=%s retained=%s backend_id=%s",
            slot_name, reason, tostring(rawget(content, slot_name .. "_rarity_texture")),
            tostring(backend_id))
    end
end

local function _apply_player_weapon_icons(self)
    for content, previous in pairs(owner_frames) do
        Core.restore_owner_frames(content, previous)
    end
    local manager = Managers and Managers.player
    local ok_loadouts, loadouts = pcall(_player_loadouts, manager)
    if not ok_loadouts or type(loadouts) ~= "table" or type(self._players) ~= "table" then return 0 end

    local weapon_skins = WeaponSkins and WeaponSkins.skins
    local corrected = 0
    for index, player_data in ipairs(self._players) do
        local player = player_data.player
        -- The row may outlive its unit across death/respawn. Keep the existing
        -- skin/boolean adapter inert on an unavailable live context, and let
        -- the owner-only path fail closed after the unconditional restore.
        local ok_context, equipment, unique_id, inventory = pcall(_player_context, player)
        if not ok_context then equipment, unique_id, inventory = nil, nil, nil end
        local loadout = unique_id and loadouts[unique_id]
        local widget = self._player_list_widgets and self._player_list_widgets[index]
        local content = widget and widget.content

        if type(loadout) == "table" and type(content) == "table" then
            for _, slot_name in ipairs(WEAPON_SLOTS) do
                local item = loadout[slot_name]
                if type(item) == "table" then
                    -- #598: the VMF `others` target excludes the sender, so the
                    -- loadout-sync wrapper mirrors this exact boolean locally.
                    -- Repair both the backing item and the already-rendered frame
                    -- in this post-hook; waiting for the next vanilla refresh made
                    -- the owner's row retain the red/unique chrome for one cycle.
                    local slot_state = mod._cim_modded_slot_state
                        and mod._cim_modded_slot_state[unique_id]
                    local is_modded = slot_state and slot_state[slot_name]
                    if type(is_modded) == "boolean" then
                        item.rarity = Core.resolve_rarity(item.rarity, true, is_modded)
                        content[slot_name .. "_rarity_texture"] = UISettings
                            and UISettings.item_rarity_textures
                            and UISettings.item_rarity_textures[item.rarity]
                    end
                    local authoritative, skin, icon, reason = Core.resolve(
                        item, equipment, slot_name, weapon_skins, function(texture)
                            return UIAtlasHelper and UIAtlasHelper.has_texture_by_name
                                and UIAtlasHelper.has_texture_by_name(texture) == true
                        end)
                    local cosmetic_descriptor
                    local cosmetics = get_mod("cosmetics_tweaker")
                    local provider = cosmetics and cosmetics._cos
                        and cosmetics._cos.resolve_peer_item_presentation
                    if type(provider) == "function" then
                        local base_icon, base_display_name = UIUtils.get_ui_information_from_item(item)
                        local ok, descriptor = pcall(provider, player_data.peer_id,
                            slot_name, item, base_icon, base_display_name)
                        if ok then cosmetic_descriptor = descriptor end
                    end
                    local resolved_icon, resolved_name =
                        Core.choose_presentation(icon, cosmetic_descriptor)
                    item._cos_presentation_display_name = resolved_name
                    if authoritative then
                        item.skin = skin
                        if resolved_icon then
                            content[slot_name] = resolved_icon
                            corrected = corrected + 1
                        end
                    elseif cosmetic_descriptor and resolved_icon then
                        -- Component state can be authoritative even when the
                        -- primary skin has no local icon. Its own icon was already
                        -- renderer-gated by Cosmetics; never copy a wire resource.
                        content[slot_name] = resolved_icon
                        corrected = corrected + 1
                    elseif (reason == "skin_icon_unavailable"
                            or reason == "skin_icon_resource_unavailable") and skin
                            and not reported_unknown_skins[skin] then
                        reported_unknown_skins[skin] = true
                        pcall(printf, "[cim:246] exact equipment skin has no registered inventory icon: skin=%s slot=%s",
                            tostring(skin), tostring(slot_name))
                    end
                end
                _apply_local_cursed_frame(manager, player, equipment, inventory, slot_name, content)
            end
        end
    end
    return corrected
end

mod._cim246_apply_player_weapon_icons = _apply_player_weapon_icons
mod._cim246_tab_preview_core = Core

mod._cim_rt_register("issue598_owner_cursed_frame_is_widget_only", function()
    local item = { backend_id = "owner-probe", rarity = "cursed" }
    local textures = { cursed = "owner-probe-texture" }
    local texture = Core.owner_cursed_texture(item, "owner-probe", textures,
        function(value) return value == "owner-probe-texture" end)
    if texture ~= "owner-probe-texture" then return "exact owner texture did not resolve" end
    if Core.owner_cursed_texture(item, "other-id", textures, function() return true end) then
        return "mismatched backend instance accepted"
    end
    local content, previous = { slot_melee_rarity_texture = "promo-probe" }, {}
    Core.apply_owner_frame(content, "slot_melee", texture, previous)
    if content.slot_melee_rarity_texture ~= "owner-probe-texture" then return "widget write missing" end
    Core.restore_owner_frames(content, previous)
    if content.slot_melee_rarity_texture ~= "promo-probe" or item.rarity ~= "cursed" then
        return "widget restore changed the original identity"
    end
end)

-- _cim_consolidated_tab_presentation_hook: #246 icons, #598/#921 metadata,
-- and #598 exact local Cursed chrome share this one installed callback.
mod:hook_safe("IngamePlayerListUI", "_update_dynamic_widget_information", function(self)
    _apply_player_weapon_icons(self)
end)

return Core
