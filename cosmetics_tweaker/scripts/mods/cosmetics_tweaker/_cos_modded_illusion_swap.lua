-- Modded-realm illusion-swap owner.
--
-- This module owns the complete local crafting bypass used when CIM is absent.
-- Keeping its eight hooks and mutable request state together prevents a second
-- entry-point registration from splitting selection, crafting, and completion.

local M = {}
M.HOOK_COUNT = 8

function M.install(mod, deps)
    if mod._cos_modded_illusion_swap_owner then
        return mod._cos_modded_illusion_swap_owner
    end

    local get_mod = assert(deps.get_mod)
    local realm = deps.realm_authority
    local _with_eac_off = deps.with_eac_off or (realm and realm.with_eac_off)
    local realm_query = deps.is_modded_realm or (realm and realm.is_modded)
    if not _with_eac_off then
        local authority = mod:dofile(
            "scripts/mods/cosmetics_tweaker/_lib_modded_realm_authority")
        _with_eac_off = function(func, self, ...)
            return authority.with_eac_off(
                script_data, nil, func, self, nil, ...)
        end
        realm_query = realm_query or function()
            return authority.is_modded(script_data, 0, rawget(_G, "Development"))
        end
    end
    assert(type(_with_eac_off) == "function",
        "modded-realm authority callback required")
    assert(type(realm_query) == "function", "modded-realm query required")
    local function _is_modded()
        local ok, value = pcall(realm_query)
        return ok and value == true
    end
    local _skin_requires_unowned_dlc = assert(deps.skin_requires_unowned_dlc)
    local function dlc_denied(key)
        local ok, value = pcall(_skin_requires_unowned_dlc, key)
        return not ok or value == true
    end
    local _custom_skin_keys = assert(deps.custom_skin_keys)
    local GlowPicker = assert(deps.glow_picker)
    local _refresh_glow_editor_button = assert(deps.refresh_glow_editor_button)
    local OFFHAND_COMMIT = assert(deps.offhand_commit)
    local LA_PERSIST = assert(deps.la_persist)
    local _dbg = assert(deps.debug)
    local _trace = assert(deps.trace)
    local _fake_skin_backend_ids = {}
    local _pending_local_craft
    local denial_budget = 8
    local function deny_local(reason)
        if denial_budget > 0 then
            denial_budget = denial_budget - 1
            if type(printf) == "function" then printf("[cos:apply] blocked reason=%s", reason) end
        end
        return nil
    end

    local function _provider_owns(mod_id)
        local got_mod, candidate = pcall(get_mod, mod_id)
        if not got_mod or type(candidate) ~= "table" then return false end
        local provider = rawget(candidate, "_cim_illusion_swap_provider")
        if type(provider) ~= "table" or rawget(provider, "schema") ~= 1 then
            return false
        end
        local owns = rawget(provider, "owns_illusion_swap")
        if type(owns) ~= "function" then return false end
        local called, result = pcall(owns)
        return called and result == true
    end

    local function _legacy_public_cim_present()
        -- Public CIM 0.8.92 predates the capability provider. Preserve its
        -- established presence-based yield for backward compatibility; Dev
        -- must opt in through the explicit provider.
        local got_mod, candidate = pcall(get_mod, "cim")
        return got_mod and candidate ~= nil
    end

    local function _cim_owns_illusion_swap()
        return _legacy_public_cim_present() or _provider_owns("cim_dev")
    end

    local Presentation = deps.presentation or mod:dofile(
        "scripts/mods/cosmetics_tweaker/_lib_local_illusion_apply")
    local register_check = deps.register_check
        or (mod._cos_command_owner and mod._cos_command_owner.register)
    assert(type(register_check) == "function", "Cosmetics check registrar required")
    local presentation = Presentation.new({
        is_modded_realm = _is_modded,
        with_eac_off = _with_eac_off,
        get_generic_input_actions = deps.get_generic_input_actions or function()
            return local_require("scripts/ui/views/hero_view/windows/definitions/hero_window_item_customization_definitions").generic_input_actions
        end,
        skin_exists = function(key)
            return type(WeaponSkins) == "table" and type(WeaponSkins.skins) == "table"
                and rawget(WeaponSkins.skins, key) ~= nil
        end,
        skin_requires_unowned_dlc = dlc_denied,
        get_current_item = function(window) return window:_get_item(window._item_backend_id) end,
        default_skin_for = function(item)
            return item and item.key and WeaponSkins and WeaponSkins.default_skins
                and WeaponSkins.default_skins[item.key]
        end,
        resolve_skin_backend_id = function(key)
            local items = Managers and Managers.backend and Managers.backend:get_interface("items")
            return items and items:get_weapon_skin_from_skin_key(key)
        end,
        log_prefix = "cos:1690",
        log = function(...) if type(printf) == "function" then printf(...) end end,
    })
    register_check("issue1690_local_illusion_apply_surface", presentation.runtime_check,
        { precondition = function() return _is_modded(), "requires the modded realm" end })

    mod:hook("BackendInterfaceItemPlayfab", "get_weapon_skin_from_skin_key", function(func, self, skin_key)
        local id, item = func(self, skin_key)
        if id then return id, item end

        -- A published CIM owner must create and remember its own synthetic
        -- identity.  Returning Cosmetics' private `ct_fake_*` id here would
        -- leave CIM unable to resolve that material when its hook is outermost.
        if _cim_owns_illusion_swap() then return nil, item end

        -- ItemMasterList.__index Crashifies on unknown keys. Illusion grids can
        -- hand us LA or CT keys which are not ItemMasterList members.
        local iml_entry = rawget(ItemMasterList, skin_key)
        local handle_vanilla_eac = _is_modded() and iml_entry
            and not dlc_denied(skin_key)
        if _custom_skin_keys[skin_key] or handle_vanilla_eac then
            local fake_id = "ct_fake_" .. skin_key
            _fake_skin_backend_ids[fake_id] = skin_key
            return fake_id, {
                skin = skin_key,
                ItemId = skin_key,
                data = iml_entry,
                key = skin_key,
                rarity = iml_entry and iml_entry.rarity or "exotic",
            }
        end
    end)

    mod:hook("HeroWindowItemCustomization", "_enable_craft_button", function(func, self, enable, disable_edges)
        if _cim_owns_illusion_swap() then return func(self, enable, disable_edges) end
        if mod:get("apply_trace") then
            _dbg("[apply-trace] _enable_craft_button enable=%s recipe=%s skin_dirty=%s modded=%s",
                tostring(enable), tostring(self._current_recipe_name),
                tostring(self._skin_dirty), tostring(_is_modded()))
        end
        return presentation.on_enable(func, self, enable, disable_edges)
    end)

    mod:hook("HeroWindowItemCustomization", "_on_illusion_index_pressed", function(func, self, index, ignore_item_spawn, mark_as_equipped)
        local widget = self._illusion_widgets and self._illusion_widgets[index]
        if _cim_owns_illusion_swap() then
            local picked_skin = widget and widget.content and widget.content.skin_key
            if picked_skin then
                if GlowPicker.is_open() and not GlowPicker.is_open_for(
                    self._item_backend_id, { skin = picked_skin }) then
                    GlowPicker.close()
                end
                _refresh_glow_editor_button(self, picked_skin)
            end
            return func(self, index, ignore_item_spawn, mark_as_equipped)
        end

        _trace("INPUT PRESS illusion-grid index=%s skin=%s ignore_spawn=%s mark_equipped=%s bid=%s",
            tostring(index), tostring(widget and widget.content and widget.content.skin_key),
            tostring(ignore_item_spawn), tostring(mark_as_equipped), tostring(self._item_backend_id))
        if mod:get("apply_trace") then
            local picked_skin = widget and widget.content and widget.content.skin_key
            local current_item = self:_get_item(self._item_backend_id)
            local current_skin = current_item and current_item.skin
            if (not current_skin or current_skin == "") and current_item
                and current_item.backend_id and Managers and Managers.backend then
                local items_iface = Managers.backend:get_interface("items")
                if items_iface and items_iface.get_skin then
                    current_skin = items_iface:get_skin(current_item.backend_id)
                end
            end
            local default_skin = current_item and current_item.key
                and WeaponSkins.default_skins[current_item.key]
            local effective_current = current_skin or default_skin
            _dbg("[apply-trace] _on_illusion_index_pressed picked=%s current=%s default=%s differs=%s ignore_spawn=%s locked=%s",
                tostring(picked_skin), tostring(current_skin), tostring(default_skin),
                tostring(picked_skin ~= effective_current), tostring(ignore_item_spawn),
                tostring(widget and widget.content and widget.content.locked))
        end

        local picked_skin = widget and widget.content and widget.content.skin_key
        if picked_skin and WeaponSkins and WeaponSkins.skins then
            local entry = WeaponSkins.skins[picked_skin]
            if entry then
                mod:info("[illusion-probe] item_bid=%s picked_skin=%s matching_item=%s material_settings=%s rarity=%s",
                    tostring(self._item_backend_id), tostring(picked_skin),
                    tostring(entry.matching_item_key), tostring(entry.material_settings_name),
                    tostring(entry.rarity))
            end
        end

        if picked_skin then
            local bid = self._item_backend_id
            if GlowPicker.is_open() and not GlowPicker.is_open_for(bid, { skin = picked_skin }) then
                GlowPicker.close()
            end
            _refresh_glow_editor_button(self, picked_skin)
        end

        return presentation.on_pressed(func, self, index, ignore_item_spawn, mark_as_equipped)
    end)

    mod:hook("HeroWindowItemCustomization", "_update_state_craft_button", function(func, self, recipe_name, ...)
        if _cim_owns_illusion_swap() then return func(self, recipe_name, ...) end
        return presentation.on_state_update(func, self, recipe_name, ...)
    end)

    mod:hook("BackendInterfaceCraftingPlayfab", "craft", function(func, self, career_name, item_backend_ids, recipe_override)
        if _cim_owns_illusion_swap() or not _is_modded() then
            return func(self, career_name, item_backend_ids, recipe_override)
        end
        if recipe_override ~= nil and recipe_override ~= "apply_weapon_skin" then
            return func(self, career_name, item_backend_ids, recipe_override)
        end
        if type(item_backend_ids) ~= "table" or #item_backend_ids > 8 then
            return deny_local("material-list-invalid")
        end

        local got_items, backend_items = pcall(function()
            return Managers and Managers.backend and Managers.backend:get_interface("items")
        end)
        if not got_items or not backend_items then return deny_local("items-backend-unavailable") end
        local weapon_backend_id, skin_key
        local resolved = pcall(function()
        for index = 1, 8 do
            local bid = rawget(item_backend_ids, index)
            if bid == nil then break end
            if _fake_skin_backend_ids[bid] then
                skin_key = _fake_skin_backend_ids[bid]
            else
                local item = backend_items:get_item_from_id(bid)
                if not item then
                    local fake_items = backend_items:get_all_fake_backend_items()
                    item = fake_items and fake_items[bid]
                end
                if item then
                    local slot_type = item.data and item.data.slot_type
                    if slot_type == "melee" or slot_type == "ranged" then
                        weapon_backend_id = bid
                    elseif slot_type == "weapon_skin" then
                        skin_key = item.skin or item.key
                    end
                end
            end
        end
        end)
        if not resolved then return deny_local("material-reader-unavailable") end

        if not weapon_backend_id or not skin_key then
            if recipe_override == "apply_weapon_skin" or skin_key then return deny_local("material-identity-missing") end
            return func(self, career_name, item_backend_ids, recipe_override)
        end
        if dlc_denied(skin_key) then
            mod:echo("Cannot apply illusion — requires DLC you don't own.")
            return deny_local("dlc-not-owned")
        end

        local mirror = self._backend_mirror
        local weapon_item = type(mirror) == "table" and type(mirror._inventory_items) == "table"
            and rawget(mirror._inventory_items, weapon_backend_id)
        if type(weapon_item) ~= "table" or (weapon_item.CustomData ~= nil
                and type(weapon_item.CustomData) ~= "table") then
            return deny_local("mirror-owner-missing")
        end
        if _pending_local_craft then return deny_local("request-already-pending") end
        local allocated, id = pcall(self._new_id, self)
        if not allocated or type(id) ~= "number" or id ~= id or id == math.huge
                or id <= 0 or id ~= math.floor(id) then return deny_local("request-id-unavailable") end

        weapon_item.skin = skin_key
        weapon_item.bypass_skin_ownership_check = true
        if weapon_item.CustomData then weapon_item.CustomData.skin = skin_key end

        _pending_local_craft = { interface = self, id = id }
        mod:info("Applied illusion '%s' locally (modded realm bypass)", skin_key)
        return id, { name = "apply_weapon_skin" }
    end)

    mod:hook_safe("BackendInterfaceCraftingPlayfab", "update", function(self, dt)
        if _cim_owns_illusion_swap() then return end
        if _pending_local_craft and _pending_local_craft.interface == self then
            local pending = _pending_local_craft
            _pending_local_craft = nil
            if type(self._craft_requests) ~= "table" then
                deny_local("request-owner-torn-down")
                return
            end
            self._craft_requests[pending.id] = {}
            local backend = Managers and Managers.backend
            if backend and type(backend.dirtify_interfaces) == "function" then
                local notified = pcall(backend.dirtify_interfaces, backend)
                if not notified then deny_local("mirror-notification-failed") end
            else
                deny_local("mirror-notification-unavailable")
            end
        end
    end)

    -- Malformed local-craft stubs have no backend id. Re-present the current
    -- item instead of allowing vanilla to dereference result[1][1].
    mod:hook("HeroWindowItemCustomization", "_upgrade_item_craft_complete", function(func, self, result)
        if self and self._item_backend_id then
            mod._offhand_committed = mod._offhand_committed or {}
            mod._offhand_committed[self._item_backend_id] = true
        end
        if result and result[1] and result[1][1] then return func(self, result) end
        local item = self._item_backend_id and self:_get_item(self._item_backend_id)
        if item then
            self:_present_item(item, nil, { 0, 2, 0 })
            self._parent:_set_loadout_item(item, self._equipment_slot_name)
            self:_state_setup_upgrade()
            self:_setup_availble_states(item)
        end
    end)

    mod:hook_safe("HeroWindowItemCustomization", "_apply_weapon_skin_craft_complete", function(self, result)
        if self and self._item_backend_id then
            mod._offhand_committed = mod._offhand_committed or {}
            mod._offhand_committed[self._item_backend_id] = true
            OFFHAND_COMMIT.commit_for_backend(
                mod._pending_la_emit_on_exit, LA_PERSIST, self._item_backend_id)
            _trace("CRAFT apply_weapon_skin_craft_complete committed offhand bid=%s",
                tostring(self._item_backend_id))
            if mod._cos925_publish_and_refresh then
                pcall(mod._cos925_publish_and_refresh, self, "weapon-skin-apply")
            end
        end
        if not _cim_owns_illusion_swap() then presentation.complete(self, "cosmetic-apply-complete") end
    end)

    local owner = {
        hook_count = M.HOOK_COUNT,
        owns_illusion_swap = _cim_owns_illusion_swap,
        presentation_owner = presentation,
    }
    mod._cos_modded_illusion_swap_owner = owner
    return owner
end

return M
