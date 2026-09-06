-- Exact owner for the gear-icon illusion Apply presentation contract (#1465).
--
-- Vanilla selection, material identity, button presentation, and input
-- eligibility are separate writes.  A downstream hook can therefore leave a
-- real different-skin selection (`_skin_dirty=true`) with an invisible or
-- disabled Apply button.  This owner treats those writes as one transaction.
-- It is engine-free: the entry module supplies realm, item, DLC, and backend
-- resolvers, while this module owns the two live UI hook callbacks.

local M = { SCHEMA = 1 }
local _unpack = unpack

local function _pack(...)
    return { n = select("#", ...), ... }
end

local function _clear(values)
    if type(values) ~= "table" then return {} end
    for key in pairs(values) do values[key] = nil end
    return values
end

local function _widget_parts(self)
    local widgets = type(self) == "table" and self._widgets_by_name or nil
    local craft = type(widgets) == "table" and widgets.craft_button or nil
    local craft_content = type(craft) == "table" and craft.content or nil
    local hotspot = type(craft_content) == "table" and craft_content.button_hotspot or nil
    return widgets, craft_content, hotspot
end

local function _set_widget_state(self, enabled, disable_edges)
    local widgets, craft_content, hotspot = _widget_parts(self)
    if type(widgets) ~= "table" or type(craft_content) ~= "table"
            or type(hotspot) ~= "table" then
        return false, "craft-widget-missing"
    end

    local required = {
        "button_top_edge_left", "button_top_edge_right", "button_top_edge_glow",
        "experience_bar", "experience_bar_edge",
    }
    local missing
    for _, name in ipairs(required) do
        local widget = widgets[name]
        if not missing and (type(widget) ~= "table" or type(widget.content) ~= "table") then
            missing = name .. "-missing"
        end
    end

    local edge_visible = enabled and not disable_edges or false
    for _, name in ipairs({
        "button_top_edge_left", "button_top_edge_right", "button_top_edge_glow",
    }) do
        local widget = widgets[name]
        if type(widget) == "table" and type(widget.content) == "table" then
            widget.content.visible = edge_visible
        end
    end

    craft_content.visible = enabled == true
    hotspot.disable_button = enabled ~= true
    hotspot.is_held = false
    hotspot.input_pressed = false
    hotspot.on_release = false

    for _, name in ipairs({ "experience_bar", "experience_bar_edge" }) do
        local widget = widgets[name]
        if type(widget) == "table" and type(widget.content) == "table" then
            widget.content.visible = enabled == true
        end
    end
    return missing == nil, missing
end

function M.new(deps)
    assert(type(deps) == "table", "#1465 Apply owner requires dependencies")
    assert(type(deps.is_modded_realm) == "function", "missing realm authority")
    assert(type(deps.with_eac_off) == "function", "missing EAC bracket")
    assert(type(deps.skin_exists) == "function", "missing skin validator")
    assert(type(deps.skin_requires_unowned_dlc) == "function", "missing DLC gate")
    assert(type(deps.get_current_item) == "function", "missing item resolver")
    assert(type(deps.default_skin_for) == "function", "missing default resolver")
    assert(type(deps.resolve_skin_backend_id) == "function", "missing skin-id resolver")

    local owner = { schema = M.SCHEMA }

    local function _is_modded()
        local ok, value = pcall(deps.is_modded_realm)
        return ok and value == true
    end

    local function _skin_exists(skin_key)
        local ok, value = pcall(deps.skin_exists, skin_key)
        return ok and value == true
    end

    -- A failing ownership reader is a denial, never permission.
    local function _dlc_denied(skin_key)
        local ok, value = pcall(deps.skin_requires_unowned_dlc, skin_key)
        return not ok or value == true
    end

    local function _emit(self, plan, action, detail)
        local _, craft_content, hotspot = _widget_parts(self)
        local materials = type(self._material_items) == "table"
            and #self._material_items or 0
        local fingerprint = table.concat({
            tostring(action), tostring(plan and plan.skin_key),
            tostring(plan and plan.current_skin), tostring(self._skin_dirty),
            tostring(materials), tostring(craft_content and craft_content.visible),
            tostring(hotspot and hotspot.disable_button), tostring(detail),
        }, "|")
        if self._cim1465_last_presentation == fingerprint then return end
        self._cim1465_last_presentation = fingerprint
        if type(deps.log) == "function" then
            pcall(deps.log,
                "[cim:1465] action=%s selected=%s current=%s dirty=%s materials=%d visible=%s disabled=%s detail=%s",
                tostring(action), tostring(plan and plan.skin_key),
                tostring(plan and plan.current_skin), tostring(self._skin_dirty),
                materials, tostring(craft_content and craft_content.visible),
                tostring(hotspot and hotspot.disable_button), tostring(detail))
        end
    end

    local function _invoke_enable(self, enabled, disable_edges)
        local method = type(self) == "table" and self._enable_craft_button or nil
        if type(method) ~= "function" then return false, "enable-method-missing" end
        local ok, err = pcall(method, self, enabled, disable_edges)
        if not ok then return false, "enable-method-error:" .. tostring(err) end
        return true
    end

    local function _clear_owned_state(self)
        self._material_items = _clear(self._material_items)
        self._skin_dirty = false
        self._has_all_crafting_requirements = false
        self._cim563_pending_explicit_skin = nil
        self._cim1465_apply_owned = false
        self._craft_progress = 0
        self._playing_craft_sound = false
    end

    function owner.owns_illusion_swap()
        return true
    end

    function owner.plan(self, index, ignore_item_spawn)
        if not _is_modded() then return { owns = false, reason = "official-realm" } end
        if type(self) ~= "table" or self._current_recipe_name ~= "apply_weapon_skin" then
            return { owns = false, reason = "other-surface" }
        end
        if ignore_item_spawn == true then
            return { owns = false, reason = "presentation-only-selection" }
        end

        local widgets = self._illusion_widgets
        local widget = type(widgets) == "table" and widgets[index] or nil
        local content = type(widget) == "table" and widget.content or nil
        local skin_key = type(content) == "table" and content.skin_key or nil
        local plan = { owns = true, skin_key = skin_key }
        if type(skin_key) ~= "string" or skin_key == "" or not _skin_exists(skin_key) then
            plan.reason = "invalid-skin"
            return plan
        end
        if _dlc_denied(skin_key) then
            plan.reason = "unowned-dlc"
            return plan
        end

        -- CIM intentionally unlocks every DLC-owned illusion in the modded
        -- realm. Reassert this after downstream hooks so an ownership-only
        -- lock cannot split selection from presentation again.
        content.locked = false

        local got_item, item = pcall(deps.get_current_item, self)
        if not got_item or type(item) ~= "table" then
            plan.reason = "current-item-missing"
            return plan
        end
        local current_skin = item.skin
        if type(current_skin) ~= "string" or current_skin == "" then
            local got_default, default_skin = pcall(deps.default_skin_for, item)
            if not got_default then
                plan.reason = "default-skin-error"
                return plan
            end
            if type(default_skin) ~= "string" or default_skin == "" then
                plan.reason = "current-skin-missing"
                return plan
            end
            current_skin = default_skin
        end
        plan.current_skin = current_skin
        if skin_key == current_skin then
            plan.reason = "already-current"
            return plan
        end

        local got_id, backend_id = pcall(deps.resolve_skin_backend_id, skin_key)
        if not got_id or type(backend_id) ~= "string" or backend_id == "" then
            plan.reason = "skin-backend-id-missing"
            return plan
        end
        plan.enable = true
        plan.backend_id = backend_id
        plan.reason = "different-valid-skin"
        return plan
    end

    function owner.release(self, reason, force)
        if type(self) ~= "table" then return false, "window-missing" end
        if force ~= true and self._cim1465_apply_owned ~= true then
            return false, "not-owned"
        end
        _invoke_enable(self, false, nil)
        _clear_owned_state(self)
        _set_widget_state(self, false, nil)
        _emit(self, nil, "released", reason or "release")
        return true
    end

    -- Vanilla calls `_enable_craft_button(false)` inside Apply completion
    -- before hook-safe observers run.  Preserve the selected semantic key for
    -- persistence, then release every adapter-owned input/presentation field
    -- so the desktop progress bar and controller requirements cannot remain
    -- live after the button disappears.
    function owner.complete(self, reason)
        if type(self) ~= "table" then return nil, false, "window-missing" end
        local pending_skin = self._cim563_pending_explicit_skin
        self._cim563_pending_explicit_skin = nil
        local released, detail = owner.release(self, reason or "craft-complete")
        return pending_skin, released, detail
    end

    function owner.enforce(self, plan)
        if type(self) ~= "table" or type(plan) ~= "table" or plan.owns ~= true then
            return false, "not-owned"
        end
        if plan.enable ~= true then
            owner.release(self, plan.reason or "disabled", true)
            return true, plan.reason
        end

        local complete, missing = _set_widget_state(self, true, true)
        if not complete then
            _clear_owned_state(self)
            _set_widget_state(self, false, nil)
            _emit(self, plan, "denied", missing)
            return false, missing
        end

        self._material_items = _clear(self._material_items)
        self._material_items[1] = plan.backend_id
        self._skin_dirty = true
        self._has_all_crafting_requirements = true
        self._cim563_pending_explicit_skin = plan.skin_key
        self._cim1465_apply_owned = true
        self._craft_progress = 0

        -- Traverse the real method so vanilla updates its generic input
        -- actions. Then write the complete visual/hotspot postcondition after
        -- every downstream hook has returned.
        local invoked, invoke_err = _invoke_enable(self, true, true)
        if not invoked then
            _clear_owned_state(self)
            _set_widget_state(self, false, nil)
            _emit(self, plan, "denied", invoke_err)
            return false, invoke_err
        end
        local applied, apply_err = _set_widget_state(self, true, true)
        if not applied then
            _clear_owned_state(self)
            _set_widget_state(self, false, nil)
            _emit(self, plan, "denied", apply_err)
            return false, apply_err
        end
        _emit(self, plan, "enabled", plan.reason)
        return true
    end

    function owner.on_enable(func, self, enable, disable_edges)
        local results
        if enable and _is_modded() and type(self) == "table"
                and self._current_recipe_name == "apply_weapon_skin" then
            results = _pack(deps.with_eac_off(func, self, enable, disable_edges))
        else
            results = _pack(func(self, enable, disable_edges))
        end
        if not enable and _is_modded() and type(self) == "table"
                and self._current_recipe_name == "apply_weapon_skin" then
            _set_widget_state(self, false, nil)
        end
        return _unpack(results, 1, results.n)
    end

    function owner.on_pressed(func, self, index, ignore_item_spawn, mark_as_equipped)
        local owns_surface = _is_modded() and type(self) == "table"
            and self._current_recipe_name == "apply_weapon_skin"
            and ignore_item_spawn ~= true
        if owns_surface then
            local complete, missing = _set_widget_state(self, false, nil)
            if not complete then
                _clear_owned_state(self)
                _emit(self, nil, "denied", missing)
                return nil
            end
            local widget = type(self._illusion_widgets) == "table"
                and self._illusion_widgets[index] or nil
            local content = type(widget) == "table" and widget.content or nil
            local skin_key = type(content) == "table" and content.skin_key or nil
            if type(skin_key) == "string" and _skin_exists(skin_key)
                    and not _dlc_denied(skin_key) then
                content.locked = false
            end
        end

        local results = _pack(func(self, index, ignore_item_spawn, mark_as_equipped))
        if owns_surface then
            owner.enforce(self, owner.plan(self, index, ignore_item_spawn))
        end
        return _unpack(results, 1, results.n)
    end

    -- Named in-game regression check: prove both halves of the presentation
    -- transaction without touching the live window or backend.
    function owner.runtime_check()
        local input_action_updates = 0
        local function widget()
            return { content = { visible = false } }
        end
        local window = {
            _current_recipe_name = "apply_weapon_skin",
            _material_items = { "stale" },
            _widgets_by_name = {
                craft_button = { content = { visible = false, button_hotspot = {
                    disable_button = true, is_held = true, input_pressed = true,
                } } },
                button_top_edge_left = widget(), button_top_edge_right = widget(),
                button_top_edge_glow = widget(), experience_bar = widget(),
                experience_bar_edge = widget(),
            },
        }
        window._enable_craft_button = function(self, enabled)
            input_action_updates = input_action_updates + 1
            -- Adversarial downstream result: the owner must correct it.
            self._widgets_by_name.craft_button.content.visible = false
            self._widgets_by_name.craft_button.content.button_hotspot.disable_button = true
        end

        local enabled, err = owner.enforce(window, {
            owns = true, enable = true, skin_key = "skin_b",
            current_skin = "skin_a", backend_id = "skin-bid",
            reason = "runtime-check",
        })
        local craft = window._widgets_by_name.craft_button.content
        if not enabled or err or window._skin_dirty ~= true
                or window._has_all_crafting_requirements ~= true
                or window._material_items[1] ~= "skin-bid"
                or craft.visible ~= true or craft.button_hotspot.disable_button ~= false
                or input_action_updates ~= 1 then
            return "#1465 enable transaction failed"
        end

        local pending_skin, released = owner.complete(window, "runtime-complete")
        if window._skin_dirty ~= false or #window._material_items ~= 0
                or craft.visible ~= false or craft.button_hotspot.disable_button ~= true
                or window._cim1465_apply_owned ~= false
                or pending_skin ~= "skin_b" or released ~= true then
            return "#1465 release transaction failed"
        end
    end

    return owner
end

-- Register and advertise one complete owner. The caller invokes this only
-- after the rest of illusion_swap.lua has loaded, and publication follows
-- both hook registrations plus the named runtime check. A raised registration
-- error can therefore leave a partial VMF hook, but never a false capability
-- that tells Cosmetics to yield to it.
function M.install(mod, owner, register_check)
    assert(type(mod) == "table" and type(mod.hook) == "function",
        "#1465 Apply owner requires a hook registrar")
    assert(type(owner) == "table"
        and type(owner.on_enable) == "function"
        and type(owner.on_pressed) == "function"
        and type(owner.owns_illusion_swap) == "function"
        and type(owner.runtime_check) == "function",
        "#1465 Apply owner is incomplete")
    assert(type(register_check) == "function",
        "#1465 Apply owner requires a runtime-check registrar")

    mod:hook("HeroWindowItemCustomization", "_enable_craft_button", owner.on_enable)
    mod:hook("HeroWindowItemCustomization", "_on_illusion_index_pressed", owner.on_pressed)
    register_check("issue1465_illusion_apply_presentation", owner.runtime_check)

    local provider = {
        schema = M.SCHEMA,
        owns_illusion_swap = owner.owns_illusion_swap,
        presentation_owner = owner,
    }
    mod._cim_illusion_apply_presentation_owner = owner
    mod._cim_illusion_swap_provider = provider
    return provider
end

return M
