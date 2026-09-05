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
    assert(type(state.contract.resolve_temper_craft_source) == "function",
        "Temper-Craft source resolver required")
    assert(type(state.contract.temper_source_requires_cwv_provider) == "function",
        "Temper-Craft source classifier required")
    assert(type(state.contract.validate_temper_owned_instance) == "function",
        "Temper-Apply ownership classifier required")
    assert(type(state.contract.is_cwv_provider_key) == "function",
        "CWV provider-key classifier required")
    assert(type(state.contract.validate_mirror_ownership_token) == "function"
            and type(state.contract.rollback_mirror_item) == "function",
        "mirror ownership transaction required")
    state.loadout = assert(ctx.loadout, "loadout owner required")
    state.get_forged_record = assert(ctx.get_forged_record,
        "forged-record accessor required")
    state.get_item_master = ctx.get_item_master or function(item_key)
        local list = rawget(_G, "ItemMasterList")
        return type(list) == "table" and rawget(list, item_key) or nil
    end
    state.get_raw_mirror_item = ctx.get_raw_mirror_item or function(backend_id)
        local managers = rawget(_G, "Managers")
        local backend = managers and managers.backend
        local mirror = backend and type(backend.get_backend_mirror) == "function"
            and backend:get_backend_mirror() or nil
        local items = mirror and mirror._inventory_items
        return type(items) == "table" and rawget(items, backend_id) or nil
    end
    state.bulk_accessory_craft = assert(ctx.bulk_accessory_craft,
        "bulk accessory policy required")
    state.craft_accessory = assert(ctx.craft_accessory,
        "accessory craft callback required")
    state.inject_item = assert(ctx.inject_item, "item injector required")
    state.register_craft = ctx.register_craft or function(backend_id, weapon_data)
        return mod._cim_register_craft(backend_id, weapon_data)
    end
    state.note_craft = ctx.note_craft or function(backend_id)
        if mod._cim_note_craft_bid then mod._cim_note_craft_bid(backend_id) end
    end
    state.guid = ctx.guid or function() return Application.guid() end
    state.rollback_item = ctx.rollback_item or function(backend_id, token)
        local mirror = Managers.backend and Managers.backend:get_backend_mirror()
        return state.contract.rollback_mirror_item(mirror, backend_id, token)
    end
    state.refresh_backend = ctx.refresh_backend or function()
        local managers = rawget(_G, "Managers")
        local backend = managers and managers.backend
        if not backend then return false, "backend_unavailable" end
        if type(backend.dirtify_interfaces) == "function" then
            backend:dirtify_interfaces()
        end
        if type(backend.get_interface) ~= "function" then
            return false, "items_interface_unavailable"
        end
        local items = backend:get_interface("items")
        if type(items) ~= "table" or type(items._refresh) ~= "function" then
            return false, "items_refresh_unavailable"
        end
        items:_refresh()
        return true
    end
    state.get_cwv_seed_identity_provider = ctx.get_cwv_seed_identity_provider
        or function()
            local resolver = rawget(_G, "get_mod")
            if type(resolver) ~= "function" then return nil, "mod_absent" end
            local ok, provider_mod = pcall(resolver, "character_weapon_variants")
            if not ok or not provider_mod then return nil, "mod_absent" end
            local getter = provider_mod._cwv_get_blacksmith_seed_identity_provider
            if type(getter) ~= "function" then return nil, "provider_api_missing" end
            local got, provider, reason = pcall(getter)
            if not got then return nil, "provider_api_exception" end
            return provider, reason
        end
    state.rt_register = assert(ctx.rt_register, "runtime-check registrar required")
    state.print_line = ctx.print_line or function(fmt, ...)
        local printer = rawget(_G, "printf")
        if type(printer) == "function" then printer(fmt, ...) end
    end
    state.set_accessory_button_presentation = set_accessory_button_presentation
    state.issue1141_receipts = tonumber(state.issue1141_receipts) or 0

    local function compact(value)
        value = tostring(value or "none"):gsub("[\r\n]", " ")
        return #value > 160 and value:sub(1, 160) or value
    end

    local function emit_receipt(result, source_backend_id, raw_item_key,
            item_key, detail)
        if state.issue1141_receipts >= 8 then return end
        state.issue1141_receipts = state.issue1141_receipts + 1
        pcall(state.print_line,
            "[cim:1141] result=%s source_bid=%s raw=%s canonical=%s detail=%s receipt=%d/8",
            compact(result), compact(source_backend_id), compact(raw_item_key),
            compact(item_key), compact(detail), state.issue1141_receipts)
    end

    local function rollback_item(backend_id, token, capability)
        local callback = type(capability) == "function" and capability
            or function() return state.rollback_item(backend_id, token) end
        local called, removed, reason = pcall(
            callback)
        if not called then return false, compact(removed) end
        if removed ~= true then return false, compact(reason or "rejected") end
        local refresh_called, refreshed, refresh_reason = pcall(
            state.refresh_backend)
        if not refresh_called then
            return false, "post-rollback-refresh-exception:"
                .. compact(refreshed)
        end
        if refreshed ~= true then
            return false, "post-rollback-refresh-rejected:"
                .. compact(refresh_reason or refreshed)
        end
        return true, nil
    end

    local function cwv_seed_identity_provider()
        local called, provider, reason = pcall(
            state.get_cwv_seed_identity_provider)
        if not called then return nil, "provider_accessor_exception" end
        return provider, reason
    end

    state.commit_craft = function(weapon_data, new_backend_id, evidence)
        evidence = type(evidence) == "table" and evidence or {}
        local injected_call, injected, inject_error, ownership_token,
            rollback_capability = pcall(
            state.inject_item, weapon_data, new_backend_id)
        if not injected_call or not injected then
            local reason = injected_call and inject_error or injected
            emit_receipt("inject_rejected", evidence.source_backend_id,
                evidence.raw_item_key, weapon_data.item_key,
                compact(reason) .. "|rollback=injector-owned")
            return false, reason or "injection rejected"
        end

        local validation_call, ownership_valid = pcall(
            state.contract.validate_mirror_ownership_token,
            ownership_token, new_backend_id, weapon_data.item_key)
        if not validation_call or ownership_valid ~= true then
            local contained, containment_error = rollback_item(
                new_backend_id, ownership_token, rollback_capability)
            emit_receipt("ownership_rejected", evidence.source_backend_id,
                evidence.raw_item_key, weapon_data.item_key,
                "missing-or-mismatched-injection-token|rollback="
                    .. tostring(contained)
                    .. (containment_error and ":" .. containment_error or ""))
            return false, "injection ownership proof missing|rollback="
                .. (contained and "complete" or "failed:"
                    .. tostring(containment_error))
        end

        local registered_call, registered, register_error = pcall(
            state.register_craft, new_backend_id, weapon_data)
        if not registered_call or not registered then
            local rolled_back, rollback_error = rollback_item(
                new_backend_id, ownership_token, rollback_capability)
            local reason = registered_call and register_error or registered
            emit_receipt("persistence_rejected", evidence.source_backend_id,
                evidence.raw_item_key, weapon_data.item_key,
                compact(reason) .. "|rollback=" .. tostring(rolled_back)
                    .. (rollback_error and ":" .. rollback_error or ""))
            local failure = tostring(reason or "persistence rejected")
            if not rolled_back then
                failure = failure .. "|rollback_failed:"
                    .. tostring(rollback_error)
            end
            return false, failure
        end

        pcall(state.note_craft, new_backend_id)
        emit_receipt("registered", evidence.source_backend_id,
            evidence.raw_item_key, weapon_data.item_key,
            evidence.proof and evidence.proof.fingerprint or "ordinary")
        return true, registered
    end

    if state.installed then return state end
    state.installed = true

    local function backend_item(backend_id)
        local managers = rawget(_G, "Managers")
        local backend = managers and managers.backend
        if not backend or type(backend.get_interface) ~= "function" then
            return nil
        end
        local got_interface, items = pcall(backend.get_interface,
            backend, "items")
        if not got_interface or type(items) ~= "table"
                or type(items.get_item_from_id) ~= "function" then
            return nil
        end
        local fetched, live = pcall(items.get_item_from_id, items, backend_id)
        return fetched and type(live) == "table" and live or nil
    end

    local function selected_item(window)
        local selected, backend_id = window:_selected_item()
        if not selected then return nil, nil, nil, nil end
        local live = backend_id and backend_item(backend_id) or nil
        return selected, backend_id, live or selected, live
    end

    -- One classifier serves both the visible button and the click.  CWV rows
    -- never take the generic rarity shortcut: an exact persisted CIM record is
    -- Apply, a provider-proven Blacksmith seed is Craft, and every other
    -- CWV-shaped row is unavailable.
    local function resolve_temper_action(item, backend_id, action_item,
            live_item)
        local record_call, record = pcall(state.get_forged_record, backend_id)
        if not record_call then return nil, "owned_record_accessor_exception" end
        if record ~= nil then
            if type(live_item) ~= "table" then
                return nil, "owned_live_item_unavailable"
            end
            local master_call, master = pcall(
                state.get_item_master, record.item_key)
            if not master_call then
                return nil, "owned_master_accessor_exception"
            end
            if type(master) ~= "table" then
                return nil, "owned_master_unavailable"
            end
            local raw_call, raw_item = pcall(
                state.get_raw_mirror_item, backend_id)
            if not raw_call then
                return nil, "owned_mirror_accessor_exception"
            end
            if type(raw_item) ~= "table" then
                return nil, "owned_mirror_item_unavailable"
            end
            local checked, valid, reason = pcall(
                state.contract.validate_temper_owned_instance,
                live_item, backend_id, record, master, raw_item)
            if not checked then return nil, "owned_classifier_exception" end
            if valid ~= true then return nil, reason or "owned_item_rejected" end
            return "apply", nil, nil
        end

        local cwv_classified, needs_cwv = pcall(
            state.contract.temper_source_requires_cwv_provider,
            item, live_item, backend_id)
        if not cwv_classified then
            return nil, "source_classifier_exception"
        end
        local preliminary
        if not needs_cwv then
            local classified, action = pcall(
                state.transaction.action_for, action_item, backend_id)
            if not classified then return nil, "action_classifier_exception" end
            preliminary = action
            -- Apply is an ownership-sensitive mutation, not a rarity class.
            -- Only the exact persisted-record branch above may authorize it.
            -- A vanilla orange/red row or a foreign mod can look "modded" to
            -- the legacy rarity classifier; without our saved record and raw
            -- mirror proof it must remain inert.
            if preliminary == "apply" then
                return nil, "owned_record_required_for_apply"
            end
            if preliminary ~= "craft" then return nil, "action_unclassified" end
        end

        local provider, provider_status
        if needs_cwv then
            provider, provider_status = cwv_seed_identity_provider()
        end
        local resolved, source, source_error = pcall(
            state.contract.resolve_temper_craft_source,
            item, live_item, backend_id, provider)
        if not resolved then return nil, "source_classifier_exception" end
        if type(source) ~= "table" then
            return nil, source_error or provider_status or "source_rejected"
        end
        return "craft", nil, source
    end
    state.resolve_temper_action = resolve_temper_action

    -- Weapon Select rows carry the authored CWV key, while their one live
    -- Blacksmith seed deliberately retains the vanilla donor key. Resolve that
    -- exact seed through CWV's private provider instead of asking native
    -- get_item_from_key to guess across the mismatched identity axes.
    local function resolve_cwv_seed(item_key)
        if state.contract.is_cwv_provider_key(item_key) ~= true then
            return nil, nil, "not_cwv"
        end
        local provider, provider_status = cwv_seed_identity_provider()
        if type(provider) ~= "table" or type(provider.sample) ~= "function" then
            return nil, nil, provider_status or "provider_sample_unavailable"
        end
        local sampled, sample, sample_error = pcall(
            provider.sample, provider, item_key)
        if not sampled then return nil, nil, "provider_sample_exception" end
        if type(sample) ~= "table" or sample.item_key ~= item_key
                or type(sample.backend_id) ~= "string"
                or sample.backend_id == "" or type(sample.proof) ~= "table" then
            return nil, nil, sample_error or "provider_sample_rejected"
        end
        local live = backend_item(sample.backend_id)
        if type(live) ~= "table" then
            return nil, nil, "provider_seed_live_item_unavailable"
        end
        local action, reason, source = resolve_temper_action(
            live, sample.backend_id, live, live)
        if action ~= "craft" or type(source) ~= "table"
                or source.item_key ~= item_key
                or source.backend_id ~= sample.backend_id
                or source.fingerprint ~= sample.proof.fingerprint then
            return nil, nil, reason or "provider_seed_reconciliation_failed"
        end
        return live, sample.backend_id, source
    end
    state.resolve_cwv_seed = resolve_cwv_seed

    mod:hook_safe("HeroWindowWeaveProperties", "_set_essence_upgrade_cost",
        function(self)
            if not state.is_active() then return end
            local widgets = self._widgets_by_name
            local button = widgets and widgets.upgrade_button
            if not button then return end
            local item, backend_id, action_item, live_item = selected_item(self)
            local action = item and resolve_temper_action(
                item, backend_id, action_item, live_item)
            local label = not item and "CRAFT MODDED ACCESSORIES"
                or action == "craft" and "CRAFT"
                or action == "apply" and "APPLY"
                or "UNAVAILABLE"
            state.set_accessory_button_presentation(button, not item)
            if button.content then button.content.visible = true end
            button.content.title_text = label
            button.content.button_hotspot.disable_button = item ~= nil
                and action == nil
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

            local item, backend_id, action_item, live_item = selected_item(self)
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

            local raw_item_key = action_item
                and (action_item.key or action_item.ItemId)
                or item.data and (item.data.key or item.data.name)
            local action, action_error, source = resolve_temper_action(
                item, backend_id, action_item, live_item)
            if not action then
                emit_receipt("source_rejected", backend_id, raw_item_key,
                    nil, action_error)
                mod:warning("[cim] Temper action rejected: "
                    .. tostring(action_error))
                return
            end
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

            local item_key = source.item_key
            if not item_key then
                mod:warning("[cim] Temper Item: no selected item")
                return
            end

            local draft = state.loadout.item_draft_payload(
                self._career_name, backend_id)
            if not draft then
                mod:warning("[cim] Craft failed: staged item data unavailable")
                return
            end
            local payload = state.transaction.copy_payload(draft)
            local guid_ok, new_backend_id = pcall(state.guid)
            if not guid_ok or type(new_backend_id) ~= "string"
                    or new_backend_id == "" then
                emit_receipt("guid_rejected", backend_id, raw_item_key,
                    item_key, new_backend_id)
                mod:warning("[cim] Craft failed: backend identity unavailable")
                return
            end
            local weapon_data = {
                item_key = item_key,
                properties = payload.properties,
                traits = payload.traits,
                power_level = (mod._cim_base_power and mod._cim_base_power()) or 300,
                rarity = "modded",
                via_mirror = true,
                career_name = self._career_name,
            }
            local committed, commit_error = state.commit_craft(
                weapon_data, new_backend_id, {
                    source_backend_id = backend_id,
                    raw_item_key = raw_item_key,
                    proof = source.proof,
                })
            if not committed then
                mod:warning("[cim] Craft failed: " .. tostring(commit_error))
                return
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

    state.rt_register("issue1141_temper_blacksmith_exact_identity", function()
        local provider, provider_status = cwv_seed_identity_provider()
        if provider_status == "mod_absent" then
            return "skip: Character Weapon Variants is not active"
        end
        if type(provider) ~= "table" then
            return "#1141 CWV seed identity provider unavailable: "
                .. tostring(provider_status)
        end
        if type(provider.sample) ~= "function" then
            return "#1141 CWV provider sample API missing"
        end
        local exact_key = "cwv_es_dual_swords"
        local sampled, sample, sample_error = pcall(
            provider.sample, provider, exact_key)
        if not sampled then
            return "#1141 CWV provider sample threw: "
                .. tostring(sample)
        end
        if type(sample) ~= "table" or type(sample.proof) ~= "table" then
            return "#1141 no registered Imperial Dual Swords Blacksmith seed: "
                .. tostring(sample_error)
        end
        local live = backend_item(sample.backend_id)
        if type(live) ~= "table" then
            return "#1141 live Imperial Dual Swords seed unavailable"
        end
        local action, reason, source = resolve_temper_action(
            live, sample.backend_id, live, live)
        if action ~= "craft" or type(source) ~= "table"
                or source.item_key ~= sample.item_key
                or source.fingerprint ~= sample.proof.fingerprint then
            return "#1141 live CWV seed resolution failed: expected="
                .. tostring(sample.item_key) .. " actual="
                .. tostring(source and source.item_key)
                .. " reason=" .. tostring(reason)
        end

        local conflict = {}
        for key, value in pairs(live) do conflict[key] = value end
        conflict.cwv_key = sample.item_key .. "_conflict"
        local conflicting = resolve_temper_action(
            conflict, sample.backend_id, conflict, live)
        if conflicting ~= nil then
            return "#1141 contradictory CWV source evidence was accepted"
        end

        local mirror_backend_id = "cim-1141-runtime-check"
        local item_master_list = rawget(_G, "ItemMasterList")
        local master = type(item_master_list) == "table"
            and rawget(item_master_list, exact_key) or nil
        local expected, gate_error = state.contract.gate_record(
            "mirror_injection", mirror_backend_id, {
            item_key = exact_key,
            rarity = "modded",
            power_level = 300,
            traits = {},
            properties = {},
            via_mirror = true,
        }, master)
        if not expected then
            return "#1141 mirror gate rejected: " .. tostring(gate_error)
        end
        local json = rawget(_G, "cjson")
        if type(json) ~= "table" or type(json.encode) ~= "function" then
            return "#1141 cjson encoder unavailable"
        end
        local payload, payload_error, mirror_record =
            state.contract.build_mirror_payload(expected, master,
                json and json.encode)
        if not payload then
            return "#1141 mirror payload rejected: "
                .. tostring(payload_error)
        end
        local mirror = { _inventory_items = {} }
        function mirror:add_item(backend_id, item)
            self._inventory_items[backend_id] = item
            item.backend_id, item.key, item.data = backend_id, item.ItemId,
                master
            item.rarity, item.power_level = "modded", 300
            item.traits, item.properties = {}, {}
        end
        function mirror:remove_item(backend_id)
            self._inventory_items[backend_id] = nil
        end
        local injected, injection_error, token, _, rollback =
            state.contract.inject_mirror_item(mirror, mirror_backend_id,
                payload, function() return "issue1141-runtime-check" end,
                mirror_record)
        if not injected or type(token) ~= "table"
                or type(rollback) ~= "function" then
            return "#1141 mirror transaction rejected: "
                .. tostring(injection_error)
        end
        local rolled_back, rollback_error = rollback()
        if rolled_back ~= true
                or mirror._inventory_items[mirror_backend_id] ~= nil then
            return "#1141 mirror rollback rejected: "
                .. tostring(rollback_error)
        end
    end)

    return state
end

return install
