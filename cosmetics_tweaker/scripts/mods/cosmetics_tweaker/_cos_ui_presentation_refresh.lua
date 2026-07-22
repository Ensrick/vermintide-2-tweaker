-- _cos_ui_presentation_refresh.lua
-- #925 retained item-card refresh and cross-mod presentation invalidation.

local M = {}

function M.install(mod, context)
    context = context or {}
    local lib = mod:dofile(
        "scripts/mods/cosmetics_tweaker/_lib_ui_presentation_refresh")
    local client, attach_error = lib.attach(_G, "cosmetics", 32)
    local la_bridge = context.la_bridge or {}

    mod._ui_presentation_refresh_lib = lib
    mod._ui_presentation_refresh = client
    mod._ui_presentation_refresh_error = attach_error
    mod._cos925_reported = mod._cos925_reported or {}

    -- Vanilla writes this retained card only from _present_item (source
    -- hero_window_item_customization.lua:1347-1381). Cosmetics commits exact
    -- offhand/icon ownership after vanilla's final write, so refresh only the
    -- same five fields from the same canonical UI resolver.
    mod._cos925_publish_and_refresh = function(window, reason)
        local backend_id = window and window._item_backend_id
        if not backend_id then return false, "missing-backend-id" end
        local item = nil
        local ok_item = window._get_item and pcall(function()
            item = window:_get_item(backend_id)
        end)
        if not ok_item then return false, "item-resolution-failed" end
        local widget = window._widgets_by_name
            and window._widgets_by_name.item_setting
        local content = widget and widget.content
        if not (item and content and UIUtils
                and UIUtils.get_ui_information_from_item) then
            return false, "surface-unavailable"
        end

        if not (UISettings and UISettings.item_rarity_textures)
                or type(Localize) ~= "function" then
            return false, "presentation-contract-unavailable"
        end
        local ok_ui, icon, display_name = pcall(
            UIUtils.get_ui_information_from_item, item)
        if not ok_ui then return false, "ui-resolution-failed" end
        local item_data = item.data or {}
        local ok_refresh, old_icon, new_icon = lib.refresh_item_card(content,
            item, icon, display_name, Localize, UISettings.item_rarity_textures)
        if not ok_refresh then return false, old_icon end

        local generation = client and client:publish({
            kind = "item-presentation",
            reason = reason or "apply",
            backend_id = backend_id,
            item_key = item.key or item_data.name,
            skin_key = item.skin,
        })
        local report_key = table.concat({ tostring(backend_id), tostring(reason),
            tostring(old_icon), tostring(new_icon) }, "|")
        if not mod._cos925_reported[report_key]
                and #mod._cos925_reported < 16 then
            mod._cos925_reported[report_key] = true
            mod._cos925_reported[#mod._cos925_reported + 1] = report_key
            pcall(printf, "[cos:925] surface=item-setting bid=%s reason=%s old=%s new=%s generation=%s",
                tostring(backend_id), tostring(reason), tostring(old_icon),
                tostring(new_icon), tostring(generation or "none"))
        end
        return true
    end

    -- Publish exact local loadout mutations for DCP and other presentation
    -- adapters. The caller composes this with Cosmetics' existing singleton
    -- BackendUtils.set_loadout_item hook rather than registering another hook.
    mod._cos925_publish_loadout = function(items_iface, backend_id, career_name,
            slot_name, reason)
        if not client then return end
        local item = nil
        if items_iface and type(items_iface.get_item_from_id) == "function" then
            pcall(function() item = items_iface:get_item_from_id(backend_id) end)
        end
        local item_data = item and item.data or nil
        local item_key = item and (item.key or (item_data and item_data.name))
        if la_bridge.backend_to_vanilla then
            item_key = la_bridge.backend_to_vanilla[backend_id] or item_key
        end
        -- BackendUtils only receives valid inventory instances in normal use.
        -- If another mod supplies an opaque instance that this interface cannot
        -- resolve, do not publish a synthetic clear for downstream consumers.
        if type(item_key) ~= "string" or item_key == "" then
            return nil, "item-unresolved"
        end
        return client:publish({
            kind = "loadout",
            reason = reason or "equip",
            career_name = career_name,
            slot_name = slot_name,
            backend_id = backend_id,
            item_key = item_key,
        })
    end

    local rt_register = context.rt_register
    if type(rt_register) == "function" then
        rt_register("issue925_live_item_icon_refresh", function()
            if not client then
                return "shared presentation ledger unavailable: "
                    .. tostring(attach_error)
            end
            if type(mod._cos925_publish_and_refresh) ~= "function"
                    or type(mod._cos925_publish_loadout) ~= "function" then
                return "Cosmetics presentation publisher/active-widget adapter missing"
            end
            local stats = client:stats()
            if stats.capacity > 128 or stats.retained > stats.capacity then
                return "shared presentation ledger exceeded its bounded capacity"
            end
        end)
    end
end

return M
