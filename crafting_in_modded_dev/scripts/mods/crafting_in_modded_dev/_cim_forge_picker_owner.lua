-- OWNER: CIM-dev Athanor picker category lifecycle.
-- RESPONSIBILITY: Seed unknown picker categories, surface native/freedom options,
-- restore temporarily widened category arrays, and guard the two picker hooks.
-- PUBLIC SURFACE: mod._cim_forge_picker_owner plus the five legacy
-- mod._cim_{ensure_weave_category_pools,ensure_trait_twin,
-- ensure_property_twin,apply_forge_freedom,restore_forge_freedom} adapters.
-- INSTALL ORDER: HeroWindowWeaveProperties._setup_menu_options, then
-- HeroWindowWeaveProperties._sync_backend_loadout at the original entry boundary.
-- INVARIANTS: One stable private dispatcher and backup store survive reload;
-- dependencies refresh before the install guard; every install exhaustively
-- republishes the replaceable public map; hooks register once and retain only
-- private dispatch; restore owns every temporary category replacement; no
-- inventory, loadout, backend-write, or wire state.
-- Owned by: crafting_in_modded_dev.lua at the original picker-hook boundary.
-- Consumed via: one mod:dofile installer call plus the republished
-- mod._cim_forge_picker_owner and flat mod._cim_* compatibility adapters.

return function(ctx)
    assert(type(ctx) == "table", "CIM forge picker owner requires context")

    local mod = assert(ctx.mod, "CIM forge picker owner requires mod")
    local state = mod._cim_forge_picker_owner_state
    if not state then
        state = {
            backup = { traits = {}, properties = {} },
        }
        mod._cim_forge_picker_owner_state = state
    end

    -- A development reload can replace every injected resolver while the
    -- Athanor is still open. Settle the previous transaction against its old
    -- targets before accepting the replacement dependencies.
    if state.restore_forge_freedom then
        state.restore_forge_freedom()
    end

    -- Refresh every late/runtime dependency before the install guard. VMF dofile
    -- is not a singleton, and callbacks registered by the first install must see
    -- the newest accessors after a development reload.
    state.is_active = assert(ctx.is_active,
        "CIM forge picker owner requires active-state accessor")
    state.get_global = assert(ctx.get_global,
        "CIM forge picker owner requires global resolver")
    state.get_setting = assert(ctx.get_setting,
        "CIM forge picker owner requires setting resolver")
    state.get_all_trait_entries = assert(ctx.get_all_trait_entries,
        "CIM forge picker owner requires all-trait resolver")
    state.get_cw_trait_entries = assert(ctx.get_cw_trait_entries,
        "CIM forge picker owner requires CW-trait resolver")
    state.get_all_property_keys = assert(ctx.get_all_property_keys,
        "CIM forge picker owner requires property resolver")
    state.print_line = assert(ctx.print_line,
        "CIM forge picker owner requires log printer")

    local function _global(name)
        return state.get_global(name)
    end

    -- Unknown adventure/CW category names otherwise reach ipairs(nil) inside the
    -- vanilla picker. Seed only categories present in the current progression.
    local function _ensure_weave_category_pools(career_name, slots_progression)
        if not slots_progression then return end
        local wt = _global("WeaveTraits")
        local wp = _global("WeaveProperties")
        local wls = _global("WeaveLoadoutSettings")

        local function _seed(pool, progression)
            if not (pool and progression) then return end
            for _, slot_unlock in ipairs(progression) do
                local category = slot_unlock.category
                if category ~= nil and pool[category] == nil then
                    pool[category] = {}
                end
            end
        end

        _seed(wt and wt.categories, slots_progression.traits)
        _seed(wp and wp.categories, slots_progression.properties)
        local loadout = wls and career_name and wls[career_name]
        _seed(loadout and loadout.talent_tree, slots_progression.talents)
    end

    local function _ensure_trait_twin(bare)
        local weave_traits = _global("WeaveTraits")
        local weapon_traits = _global("WeaponTraits")
        if not (weave_traits and weave_traits.traits
            and weapon_traits and weapon_traits.traits) then
            return nil
        end
        local weave_key = "weave_" .. bare
        if weave_traits.traits[weave_key] then return weave_key end
        local adventure = weapon_traits.traits[bare]
        if not (adventure and adventure.display_name) then return nil end
        weave_traits.traits[weave_key] = {
            name = weave_key,
            display_name = adventure.display_name,
            icon = adventure.icon,
            buff_name = adventure.buff_name,
            -- This is a matched pair from one native entry. Dropping only values
            -- recreates the string.format crash guarded by issue #238.
            advanced_description = adventure.advanced_description,
            description_values = adventure.description_values,
        }
        return weave_key
    end

    local function _ensure_property_twin(bare)
        local weave_properties = _global("WeaveProperties")
        local weapon_properties = _global("WeaponProperties")
        if not (weave_properties and weave_properties.properties
            and weapon_properties and weapon_properties.properties) then
            return nil
        end
        local weave_key = "weave_" .. bare
        if weave_properties.properties[weave_key] then return weave_key end
        local adventure = weapon_properties.properties[bare]
        if not (adventure and adventure.display_name and adventure.buff_name) then
            return nil
        end
        local buff_templates = _global("BuffTemplates")
        local template = buff_templates and buff_templates[adventure.buff_name]
        if not (template and template.buffs and template.buffs[1]) then return nil end
        local description_values = adventure.description_values
        if not (type(description_values) == "table" and description_values[1]
            and type(description_values[1].value) == "number") then
            description_values = { { value_type = "percent", value = 0.05 } }
        end
        weave_properties.properties[weave_key] = {
            name = weave_key,
            display_name = adventure.display_name,
            icon = adventure.icon or "icons_placeholder",
            category = adventure.category or "offensive",
            buff_name = adventure.buff_name,
            description_values = description_values,
        }
        return weave_key
    end

    local function _wanted_trait_bares(slot_type)
        local out = {}
        local entries
        if state.get_setting("allow_any_trait_property") then
            entries = state.get_all_trait_entries()
        elseif state.get_setting("allow_cw_traits") then
            entries = state.get_cw_trait_entries(slot_type)
        end
        for _, entry in ipairs(entries or {}) do
            if entry and entry[1] then out[#out + 1] = entry[1] end
        end
        return out
    end

    local function _wanted_property_bares()
        if not state.get_setting("allow_any_trait_property") then return {} end
        return state.get_all_property_keys() or {}
    end

    -- category is the item's native trait_table_name/property_table_name. Seed
    -- its own Adventure pool before adding freedom-toggle extras (#404).
    local function _native_bares_for(kind, category)
        local out = {}
        if not category then return out end
        if kind == "traits" then
            local weapon_traits = _global("WeaponTraits")
            local pool = weapon_traits and weapon_traits.combinations
                and weapon_traits.combinations[category]
            if type(pool) == "table" then
                for _, entry in ipairs(pool) do
                    local key = entry and entry[1]
                    if key then out[#out + 1] = key end
                end
            end
        else
            local weapon_properties = _global("WeaponProperties")
            local combinations = weapon_properties and weapon_properties.combinations
                and weapon_properties.combinations[category]
            local exotic = type(combinations) == "table" and combinations.exotic
            if type(exotic) == "table" then
                for _, combination in ipairs(exotic) do
                    if type(combination) == "table" then
                        for _, key in ipairs(combination) do
                            if key then out[#out + 1] = key end
                        end
                    end
                end
            end
        end
        return out
    end

    local function _widen_category(kind, categories, category, wanted, ensure_twin)
        if not (categories and category) then return end
        local backup = state.backup[kind]
        if backup[category] == nil then
            backup[category] = {
                target = categories,
                original = categories[category] or false,
            }
        end
        local original = backup[category].original
        local base = type(original) == "table" and original or {}
        local seen, widened = {}, {}
        for _, key in ipairs(base) do
            if not seen[key] then
                seen[key] = true
                widened[#widened + 1] = key
            end
        end
        for _, bare in ipairs(_native_bares_for(kind, category)) do
            local weave_key = ensure_twin(bare)
            if weave_key and not seen[weave_key] then
                seen[weave_key] = true
                widened[#widened + 1] = weave_key
            end
        end
        for _, bare in ipairs(wanted) do
            local weave_key = ensure_twin(bare)
            if weave_key and not seen[weave_key] then
                seen[weave_key] = true
                widened[#widened + 1] = weave_key
            end
        end
        categories[category] = widened
    end

    local function _apply_forge_freedom(slots_progression, slot_type)
        if not slots_progression then return end
        local weave_traits = _global("WeaveTraits")
        local weave_properties = _global("WeaveProperties")
        local trait_bares = _wanted_trait_bares(slot_type)
        local property_bares = _wanted_property_bares()

        if weave_traits and weave_traits.categories and slots_progression.traits then
            local done = {}
            for _, slot_unlock in ipairs(slots_progression.traits) do
                local category = slot_unlock and slot_unlock.category
                if category and not done[category] then
                    done[category] = true
                    _widen_category("traits", weave_traits.categories, category,
                        trait_bares, _ensure_trait_twin)
                end
            end
        end
        if weave_properties and weave_properties.categories
            and slots_progression.properties then
            local done = {}
            for _, slot_unlock in ipairs(slots_progression.properties) do
                local category = slot_unlock and slot_unlock.category
                if category and not done[category] then
                    done[category] = true
                    _widen_category("properties", weave_properties.categories,
                        category, property_bares, _ensure_property_twin)
                end
            end
        end
    end

    local function _restore_forge_freedom()
        for category, record in pairs(state.backup.traits) do
            local target = record.target
            local original = record.original
            if target then
                target[category] = type(original) == "table" and original or nil
            end
        end
        for category, record in pairs(state.backup.properties) do
            local target = record.target
            local original = record.original
            if target then
                target[category] = type(original) == "table" and original or nil
            end
        end
        state.backup.traits = {}
        state.backup.properties = {}
    end

    -- Stable private dispatchers let installed callbacks consume updated
    -- implementations without depending on replaceable public namespace identity.
    state.ensure_weave_category_pools = _ensure_weave_category_pools
    state.ensure_trait_twin = _ensure_trait_twin
    state.ensure_property_twin = _ensure_property_twin
    state.apply_forge_freedom = _apply_forge_freedom
    state.restore_forge_freedom = _restore_forge_freedom

    local dispatch = state.dispatch
    if not dispatch then
        dispatch = {
            ensure_weave_category_pools = function(...)
                return state.ensure_weave_category_pools(...)
            end,
            ensure_trait_twin = function(...)
                return state.ensure_trait_twin(...)
            end,
            ensure_property_twin = function(...)
                return state.ensure_property_twin(...)
            end,
            apply_forge_freedom = function(...)
                return state.apply_forge_freedom(...)
            end,
            restore_forge_freedom = function(...)
                return state.restore_forge_freedom(...)
            end,
        }
        state.dispatch = dispatch
    end

    -- PROJECT_STANDARDS 2.2a rule 10: public namespace tables are replaceable.
    -- Republish exhaustively on EVERY installer call, even after registration is
    -- already complete. Clear foreign/stale keys so the public contract remains
    -- exactly five operations rather than accumulating reload residue.
    local owner = mod._cim_forge_picker_owner
    if type(owner) ~= "table" then owner = {} end
    for key in pairs(owner) do owner[key] = nil end
    owner.ensure_weave_category_pools = dispatch.ensure_weave_category_pools
    owner.ensure_trait_twin = dispatch.ensure_trait_twin
    owner.ensure_property_twin = dispatch.ensure_property_twin
    owner.apply_forge_freedom = dispatch.apply_forge_freedom
    owner.restore_forge_freedom = dispatch.restore_forge_freedom
    mod._cim_forge_picker_owner = owner

    -- Preserve the established flat regression API from private dispatch, not
    -- from a public table another reload is allowed to replace.
    mod._cim_ensure_weave_category_pools = dispatch.ensure_weave_category_pools
    mod._cim_ensure_trait_twin = dispatch.ensure_trait_twin
    mod._cim_ensure_property_twin = dispatch.ensure_property_twin
    mod._cim_apply_forge_freedom = dispatch.apply_forge_freedom
    mod._cim_restore_forge_freedom = dispatch.restore_forge_freedom

    if state.installed then return owner end
    state.installed = true

    mod:hook("HeroWindowWeaveProperties", "_setup_menu_options",
        function(func, self, career_name, slots_progression)
            dispatch.ensure_weave_category_pools(career_name, slots_progression)
            if state.is_active() then
                local selected_item = self._selected_item and self:_selected_item()
                local slot_type = selected_item and selected_item.data
                    and selected_item.data.slot_type
                pcall(dispatch.apply_forge_freedom, slots_progression, slot_type)
            end
            return func(self, career_name, slots_progression)
        end)

    mod:hook("HeroWindowWeaveProperties", "_sync_backend_loadout",
        function(func, self)
            if not state.is_active() then return func(self) end
            local ok, err = pcall(func, self)
            if not ok then
                state.print_line("[cim:404] _sync_backend_loadout threw (weave tooltip nil for adventure/CW category) — completing _populate_menu_widgets: %s",
                    tostring(err))
                mod:warning("[cim] _sync_backend_loadout guarded (deus/CW weave-tooltip nil): %s",
                    tostring(err))
                pcall(self._populate_menu_widgets, self)
            end
        end)

    return owner
end
