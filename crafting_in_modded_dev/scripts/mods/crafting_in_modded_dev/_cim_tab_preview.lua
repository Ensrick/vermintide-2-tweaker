-- Hold-Tab player weapon icon correction (#246).
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

local function _apply_player_weapon_icons(self)
    local manager = Managers and Managers.player
    local loadouts = manager and manager:player_loadouts()
    if type(loadouts) ~= "table" or type(self._players) ~= "table" then return 0 end

    local weapon_skins = WeaponSkins and WeaponSkins.skins
    local corrected = 0
    for index, player_data in ipairs(self._players) do
        local player = player_data.player
        local player_unit = player and player.player_unit
        local inventory = player_unit and ALIVE[player_unit]
            and ScriptUnit.has_extension(player_unit, "inventory_system")
        local equipment = inventory and inventory:equipment()
        local unique_id = player and player:unique_id()
        local loadout = unique_id and loadouts[unique_id]
        local widget = self._player_list_widgets and self._player_list_widgets[index]
        local content = widget and widget.content

        if type(loadout) == "table" and type(content) == "table" then
            for _, slot_name in ipairs(WEAPON_SLOTS) do
                local item = loadout[slot_name]
                local authoritative, skin, icon, reason = Core.resolve(
                    item, equipment, slot_name, weapon_skins)
                if authoritative then
                    item.skin = skin
                    if icon then
                        content[slot_name] = icon
                        corrected = corrected + 1
                    end
                elseif reason == "skin_icon_unavailable" and skin
                        and not reported_unknown_skins[skin] then
                    reported_unknown_skins[skin] = true
                    pcall(printf, "[cim:246] exact equipment skin has no registered inventory icon: skin=%s slot=%s",
                        tostring(skin), tostring(slot_name))
                end
            end
        end
    end
    return corrected
end

mod._cim246_apply_player_weapon_icons = _apply_player_weapon_icons
mod._cim246_tab_preview_core = Core

mod:hook_safe("IngamePlayerListUI", "_update_dynamic_widget_information", function(self)
    _apply_player_weapon_icons(self)
end)

return Core
