-- Runtime adapter for the Athanor Temper Item draft transaction (#1141).

local function restore_default_offset(text_style)
    local offset = text_style and text_style.offset
    local default = text_style and text_style.default_offset
    if not offset or not default then return end
    for index = 1, 3 do offset[index] = default[index] end
end

local function set_accessory_button_presentation(button, accessory_mode)
    local content = button.content
    if not content then return end

    -- The native icon/icon_disabled passes share content.icon. Preserve its
    -- exact texture before suppressing both passes for #1117, then restore
    -- it when this same widget returns to a weapon editor.
    if content._cim_native_upgrade_icon == nil and content.icon ~= nil then
        content._cim_native_upgrade_icon = content.icon
    end
    if accessory_mode then
        content.icon = nil
        local style = button.style
        restore_default_offset(style and style.title_text)
        restore_default_offset(style and style.title_text_disabled)
        restore_default_offset(style and style.title_text_shadow)
    elseif content._cim_native_upgrade_icon ~= nil then
        content.icon = content._cim_native_upgrade_icon
    end
end

local function install(ctx)
    assert(type(ctx) == "table", "CIM temper runtime requires context")
    local mod = assert(ctx.mod, "CIM temper runtime requires mod")
    local state = mod._cim_temper_runtime_state or {}
    mod._cim_temper_runtime_state = state

    state.is_active = assert(ctx.is_active, "active accessor required")
    state.transaction = assert(ctx.transaction, "transaction policy required")
    state.contract = assert(ctx.contract, "synthetic item contract required")
    assert(type(state.contract.canonical_item_key) == "function",
        "canonical item-key resolver required")
    state.loadout = assert(ctx.loadout, "loadout owner required")
    state.bulk_accessory_craft = assert(ctx.bulk_accessory_craft,
        "bulk accessory policy required")
    state.craft_accessory = assert(ctx.craft_accessory,
        "accessory craft callback required")
    state.inject_item = assert(ctx.inject_item, "item injector required")
    state.set_accessory_button_presentation = set_accessory_button_presentation
    state.issue1141_receipts = tonumber(state.issue1141_receipts) or 0

    if state.installed then return state end
    state.installed = true

    local function selected_item(window)
        local selected, backend_id = window:_selected_item()
        if not selected then return nil, nil, nil end
        local items = Managers.backend and Managers.backend:get_interface("items")
        local live = backend_id and items and items:get_item_from_id(backend_id)
        return selected, backend_id, live or selected
    end

    mod:hook_safe("HeroWindowWeaveProperties", "_set_essence_upgrade_cost",
        function(self)
            if not state.is_active() then return end
            local widgets = self._widgets_by_name
            local button = widgets and widgets.upgrade_button
            if not button then return end
            local item, backend_id, live_item = selected_item(self)
            local action = item and state.transaction.action_for(live_item, backend_id)
            local label = not item and "CRAFT MODDED ACCESSORIES"
                or action == "craft" and "CRAFT"
                or "APPLY"
            state.set_accessory_button_presentation(button, not item)
            if button.content then button.content.visible = true end
            button.content.title_text = label
            button.content.button_hotspot.disable_button = false
            if button.style and button.style.price_icon then
                button.style.price_icon.color[1] = 0
            end
            if button.style and button.style.price_icon_disabled then
                button.style.price_icon_disabled.color[1] = 0
            end
            local warning = widgets.upgrade_essence_warning
            if warning and warning.content then warning.content.visible = false end
        end)

    -- Leaving the item editor is Cancel for an uncommitted weapon draft.
    mod:hook_safe("HeroWindowWeaveProperties", "on_exit", function(self)
        if not state.is_active() then return end
        local _, backend_id = self:_selected_item()
        if backend_id then
            state.loadout.discard_item_draft(self._career_name, backend_id)
        end
    end)

    mod:hook("HeroWindowWeaveProperties", "_upgrade_magic_level",
        function(func, self)
            if not state.is_active() then return func(self) end

            local item, backend_id, live_item = selected_item(self)
            if not item then
                local crafted = state.bulk_accessory_craft.craft_all(
                    function(slot_index, slot_name)
                        return state.craft_accessory(self, slot_index, slot_name)
                    end)
                if crafted == 0 then
                    mod:echo("[cim] No equipped accessories could be crafted")
                end
                return
            end

            -- #1141: CWV's real 5-power Blacksmith row deliberately retains its
            -- vanilla donor in `.key`/`.name` for engine fallback. Vanilla
            -- PlayFabMirrorBase._update_data also overwrites `item.key` from
            -- ItemId; the exact CWV identity survives in this seed's backend id.
            -- Resolve through CIM's shared contract, whose exact fields and
            -- `cwv_<key>_NNN` backend-id band outrank that donor.
            local raw_item_key = live_item and (live_item.key or live_item.ItemId)
            local item_key = state.contract.canonical_item_key(live_item, backend_id)
            if not item_key then
                mod:echo("[cim] Temper Item: no selected item")
                return
            end

            local action = state.transaction.action_for(live_item, backend_id)
            if action == "apply" then
                local ok, changed = state.loadout.apply_item_draft(
                    self._career_name, backend_id)
                if not ok then
                    mod:warning("[cim] Apply failed: " .. tostring(changed))
                    return
                end
                state.loadout.discard_item_draft(self._career_name, backend_id)
                self:_sync_backend_loadout()
                if changed then
                    mod:echo("[cim] Applied staged properties and trait")
                    if self._play_sound then
                        pcall(self._play_sound, self,
                            "play_gui_craft_forge_button_completed")
                    end
                else
                    mod:echo("[cim] No staged changes to apply")
                end
                return
            end

            local draft = state.loadout.item_draft_payload(
                self._career_name, backend_id)
            if not draft then
                mod:warning("[cim] Craft failed: staged item data unavailable")
                return
            end
            local payload = state.transaction.copy_payload(draft)
            local new_backend_id = Application.guid()
            local weapon_data = {
                item_key = item_key,
                properties = payload.properties,
                traits = payload.traits,
                power_level = (mod._cim_base_power and mod._cim_base_power()) or 300,
                rarity = "modded",
                via_mirror = true,
            }
            local injected, inject_error = state.inject_item(
                weapon_data, new_backend_id)
            if not injected then
                mod:warning("[cim] Craft failed: " .. tostring(inject_error))
                return
            end
            local registered, register_error = mod._cim_register_craft(
                new_backend_id, weapon_data)
            if not registered then
                Managers.backend:get_backend_mirror():remove_item(new_backend_id)
                mod:warning("[cim] Craft persistence rejected: "
                    .. tostring(register_error))
                return
            end
            if mod._cim_note_craft_bid then
                mod._cim_note_craft_bid(new_backend_id)
            end

            -- Exact live-test evidence without turning repeated Temper crafts
            -- into unbounded session-log traffic.
            if type(printf) == "function" and state.issue1141_receipts < 8 then
                state.issue1141_receipts = state.issue1141_receipts + 1
                pcall(printf,
                    "[cim:1141] temper_craft backend=%s raw=%s canonical=%s result=registered",
                    tostring(backend_id), tostring(raw_item_key), tostring(item_key))
            end

            local slot_name = self._params and self._params.selected_slot_name
            local display = item_key
            local master = rawget(ItemMasterList, item_key)
            if master and master.display_name then
                local ok, localized = pcall(Localize, master.display_name)
                if ok and localized then display = localized end
            end
            mod:echo("[cim] Crafted new "
                .. tostring(slot_name and slot_name:gsub("^slot_", "") or "item")
                .. ": " .. display .. " [modded] - equip from inventory")
            if self._play_sound then
                pcall(self._play_sound, self,
                    "play_gui_craft_forge_button_completed")
            end
        end)

    return state
end

return install
