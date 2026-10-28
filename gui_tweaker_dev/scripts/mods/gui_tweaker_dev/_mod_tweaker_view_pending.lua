-- _mod_tweaker_view_pending.lua -- Standalone staged settings/profile owner.
--
-- Installs the verbatim pending/Apply/Default/profile cluster on the class.
-- Its private one-view supplier adapter consumes only the view's second return,
-- after the original loader has evaluated; VMF load tuples remain untouched.
-- New binder failures are private protocol failures, not VMF dofile failures.
--
-- Owned by: gui_tweaker_dev.lua's entry manifest and named runtime contracts.
-- Consumed via: inert load and bind_view_supplier at each view supplier boundary.
-- This owner performs no nested module loads.
local M = {}
local function install(ModTweakerView, deps)
    local mod, transactions, default_reset = deps.mod, deps.transactions, deps.default_reset
    local profiles, profile_runtime, DialogueUI = deps.profiles, deps.profile_runtime, deps.DialogueUI
    local _owner, _nf, _cat_get, _cat_set = deps.owner, deps.nf, deps.cat_get, deps.cat_set
    local _mt, _printf, _play_click, _commit_keybind = deps.mt, deps.printf, deps.play_click, deps.commit_keybind
local function _cat_key(category)
    return category and category.mod_id or "?"
end

-- Stage one edit into the pending buffer (replaces the live _cat_set on every row edit).
-- Records the value + refreshes the APPLY button dirty state. (#208) The buffer is keyed by
-- the OWNER mod_id resolved from the node, so an Equipment edit to e.g. a cosmetics setting
-- buffers under "cosmetics_tweaker"; for a normal category _owner returns category.mod_id, so
-- the key is _cat_key(category) exactly as before.
function ModTweakerView:stage_set(category, setting_id, value)
    local _, owner_id = _owner(category, setting_id)
    local key = owner_id or _cat_key(category)
    self._pending[key] = self._pending[key] or {}
    self._pending[key][setting_id] = value
    self:_search_note_setting(category, setting_id)
    -- NOTE: do NOT set self._dirty here. self._dirty drives the auto-save-to-log on exit,
    -- which must reflect LIVE writes only — a pending (unapplied) edit was never written,
    -- so exiting with only-pending edits must NOT export. apply_pending sets _dirty.
    self:_update_apply_button()
end

-- Read a setting's EFFECTIVE value: the staged value if one is pending, else the live
-- value passed in (which the caller read via _cat_get). Mirrors native _get_setting
-- (assigned(pending, live)). (#208) Reads from the OWNER mod_id's buffer (see stage_set).
function ModTweakerView:get_staged(category, setting_id, live_value)
    local _, owner_id = _owner(category, setting_id)
    local p = self._pending[owner_id or _cat_key(category)]
    if p and p[setting_id] ~= nil then return p[setting_id] end
    return live_value
end

-- True if the ACTIVE category has any pending edit (drives APPLY enabled/greyed). (#208) The
-- merged Equipment category buffers under EACH member mod_id, so it's dirty if ANY member's
-- buffer is non-empty; a normal category checks its single _cat_key buffer as before.
function ModTweakerView:_active_category_dirty()
    if self._profile_replay then return true end
    local cat = self._categories and self._categories[self._selected]
    if not cat then return false end
    if default_reset.is_armed(self, cat) then return true end
    local ids = cat._owner_mod_ids
    if ids then
        for i = 1, #ids do
            local p = self._pending[ids[i]]
            if p and next(p) ~= nil then return true end
        end
        return false
    end
    local p = self._pending[_cat_key(cat)]
    return (p ~= nil) and (next(p) ~= nil)
end

-- Recompute the APPLY button's disabled flag from the active category's buffer.
function ModTweakerView:_update_apply_button()
    if self._apply then self._apply.content.disabled = not self:_active_category_dirty() end
end

-- (#561) Profile snapshots are flat maps of owner-qualified setting ids. One
-- persisted map belongs to exactly one visible tab/slot, keeping VMF's deep-copy
-- cost bounded. Slot 1 lazily adopts the user's current live settings; an unused
-- slot starts from the tab's declared defaults.
function ModTweakerView:_profile_snapshot(category, defaults)
    local out = {}
    if DialogueUI.is_category(category) then return out end
    for i = 1, #(self._build_nodes or {}) do
        local node = self._build_nodes[i]
        local sid = _nf(node, "setting_id")
        local kind = _nf(node, "type")
        -- Keybinds are device/user-global input configuration, not gameplay/UI
        -- profile state; VMF also requires a separate binding registration path.
        if sid and kind ~= "group" and kind ~= "keybind" then
            local _, owner_id = _owner(category, sid)
            local value
            if defaults then value = _nf(node, "default_value") else value = _cat_get(category, sid) end
            if value == nil and defaults then value = _cat_get(category, sid) end
            local excluded = category._profile_excluded_owners
            if owner_id and not (excluded and excluded[owner_id]) and value ~= nil then
                out[profiles.member_key(owner_id, sid)] = value
            end
        end
    end
    return profiles.capture_owners(out, category, _owner, defaults)
end

function ModTweakerView:_profile_ensure(category)
    if not category or DialogueUI.is_category(category) then return end
    if self._profile_replay then return end
    return profile_runtime.ensure_profile(self, {
        category = category, tab_id = _cat_key(category), profiles = profiles, store = mod,
        transactions = transactions, owner = _owner, set_one = _cat_set, log = _printf,
    })
end

function ModTweakerView:_profile_capture(category)
    if not category or DialogueUI.is_category(category) then return end
    local tab_id = _cat_key(category)
    local slot = profiles.get_active(mod, tab_id)
    local values, err = self:_profile_snapshot(category, false)
    if not values then
        _printf("[gut:221] profile capture deferred tab=%s error=%s", tostring(tab_id), tostring(err))
        return false
    end
    local ok, finished, saved = pcall(profile_runtime.finish_replay,
        self, category, profiles, mod, tab_id, values)
    if not ok or not finished then return false end
    slot = profiles.get_active(mod, tab_id)
    if not saved then profiles.save(mod, tab_id, slot, values) end
    self._profile_ready[tab_id .. ":" .. tostring(slot)] = true
    self._profile_slot = slot
    self:_update_apply_button()
    return true
end

function ModTweakerView:_switch_profile(slot)
    local category = self._categories and self._categories[self._selected]
    if not category or DialogueUI.is_category(category) then return end
    local tab_id = _cat_key(category)
    local ok, err = profile_runtime.switch_profile(self, slot, {
        category = category, tab_id = tab_id, profiles = profiles, store = mod,
        transactions = transactions, owner = _owner, log = _printf,
        on_complete = function(id)
            local mt = _mt()
            if mt and mt.emit_profile_diagnostic then mt:emit_profile_diagnostic(id, "profile_switch") end
        end,
    })
    if not ok then
        _printf("[gut:221] profile switch deferred tab=%s profile=%d error=%s",
            tostring(tab_id), slot, tostring(err))
        return
    end
    _play_click()
end

-- (#446) Mutually-exclusive group enforcement. `setting_id` (a checkbox in `category`)
-- was just switched ON; stage every OTHER member of its registered exclusive group OFF,
-- so at most one member is ever ON. Members are keyed by their REGISTERED (mod_id,
-- setting_id) and staged DIRECTLY into the pending buffer under the member's OWN mod_id
-- -- the same key stage_set resolves via _owner for a same-mod member, and the correct
-- per-mod buffer for a cross-mod member, so a sibling living in another tab still commits
-- when that tab is applied. Only a member whose EFFECTIVE value (staged, else the member
-- mod's live get) is currently truthy is written, so we never manufacture a false-dirty
-- edit. Returns true if any sibling changed -- the caller then rebuilds so the switched-
-- off rows repaint (checkbox display is cached; only a row rebuild re-reads the staged
-- flag).
function ModTweakerView:_enforce_exclusive(category, setting_id)
    local MT = _mt()
    if not MT or type(MT.get_exclusive_group_id) ~= "function" then return false end
    local _, owner_id = _owner(category, setting_id)
    if not owner_id then return false end
    local gid = MT:get_exclusive_group_id(owner_id, setting_id)
    if not gid then return false end
    local members = MT:get_exclusive_members(gid)
    if type(members) ~= "table" then return false end
    local changed = false
    for i = 1, #members do
        local m = members[i]
        if not (m.mod_id == owner_id and m.setting_id == setting_id) then
            local p = self._pending[m.mod_id]
            local eff
            if p and p[m.setting_id] ~= nil then
                eff = p[m.setting_id]
            else
                local mo = get_mod(m.mod_id)
                if mo then local ok, v = pcall(mo.get, mo, m.setting_id); if ok then eff = v end end
                if eff == nil and MT.get then eff = MT:get(m.mod_id, m.setting_id) end
            end
            if eff then
                self._pending[m.mod_id] = self._pending[m.mod_id] or {}
                self._pending[m.mod_id][m.setting_id] = false
                changed = true
            end
        end
    end
    if changed then self:_update_apply_button() end
    return changed
end

-- APPLY: commit the whole pending buffer for `category` through the existing _cat_set
-- path (the ONLY place _cat_set runs on edit — a stray slider drag never takes effect
-- until clicked), clear the buffer, grey the button, and repaint the rows from the new
-- live values. Native handle_apply_button -> apply_changes (options_view.lua:1919).
-- (#208) For the merged Equipment category, flush EACH member mod_id's buffer (each edit
-- routes to its owner's mod_obj via _cat_set -> _owners), re-register any keybinds across
-- the committed settings, then clear them all.
function ModTweakerView:apply_pending(category)
    -- Missing/replaced CD retains the draft; never use shadow persistence.
    if DialogueUI.is_category(category) and not DialogueUI.can_apply(category) then
        _printf("[gut:998] apply_deferred owner_unavailable")
        return
    end
    if self._profile_replay then
        local pending = false
        for mid in pairs(self._profile_replay.contexts) do
            if next(self._pending[mid] or {}) then pending = true end
        end
        if not pending then self:_profile_capture(category); self:_update_apply_button(); return end
    end
    local MT = _mt()
    local ids = category._owner_mod_ids
    if MT and MT.prune_runtime_gated_pending and MT:prune_runtime_gated_pending(self._pending, ids or { _cat_key(category) }) > 0 then self:_update_apply_button() end
    if ids then
        local committed = {}   -- setting_id -> value across all members (for keybind re-reg)
        local any, wrote, failed = false, false, false
        for i = 1, #ids do
            local mid = ids[i]
            local p = self._pending[mid]
            if p and next(p) ~= nil then
                local count, batched, batch_err, complete = transactions.commit(category, p, _owner, _cat_set, profile_runtime.transaction_context(self, category, p, _owner))
                wrote = wrote or count > 0
                if batched then
                    printf("[gut:560] owner=%s settings=%d notifications=%d complete=%s error=%s", tostring(mid), count, batch_err and 0 or 1, tostring(complete), tostring(batch_err or "none"))
                end
                if complete then for id, value in pairs(p) do committed[id] = value end; self._pending[mid] = {}
                else failed = true end
                any = true
            end
        end
        if not any and not default_reset.is_armed(self, category) then return end
        local reset_attempted, reset_complete, reset_err = default_reset.finish(
            self, category, not failed, mod._gut_reset_modded_loadouts)
        if reset_attempted then
            _printf("[gut:1033] surface=standalone reset_complete=%s error=%s",
                tostring(reset_complete), tostring(reset_err or "none"))
        end
        -- (#123) Keybinds need VMF re-registration, not just a value set.
        for _, row in ipairs(self._rows or {}) do
            if row._is_keybind and row._setting_id and committed[row._setting_id] ~= nil then
                _commit_keybind(row, committed[row._setting_id])
            end
        end
        self._dirty = self._dirty or wrote
        self:_update_apply_button()
        self:_build_rows(category)
        if not failed then self:_profile_capture(category) end
        _play_click()
        mod:debug("[mt:apply] Equipment buffers {%s} complete=%s", table.concat(ids, ", "), tostring(not failed))
        return
    end
    local key = _cat_key(category)
    local p = self._pending[key]
    if (not p or next(p) == nil) and not default_reset.is_armed(self, category) then return end
    if not p or next(p) == nil then
        local attempted, reset_complete, reset_err = default_reset.finish(
            self, category, true, mod._gut_reset_modded_loadouts)
        if attempted then
            _printf("[gut:1033] surface=standalone reset_complete=%s error=%s",
                tostring(reset_complete), tostring(reset_err or "none"))
        end
        self:_update_apply_button()
        self:_build_rows(category)
        _play_click()
        return
    end
    local count, batched, batch_err, complete = transactions.commit(category, p, _owner, _cat_set, profile_runtime.transaction_context(self, category, p, _owner))
    if batched then
        printf("[gut:560] owner=%s settings=%d notifications=%d complete=%s error=%s", tostring(key), count, batch_err and 0 or 1, tostring(complete), tostring(batch_err or "none"))
    end
    if complete then
        for _, row in ipairs(self._rows or {}) do
            if row._is_keybind and row._setting_id and p[row._setting_id] ~= nil then
                _commit_keybind(row, p[row._setting_id])
            end
        end
    end
    if complete then self._pending[key] = {} end
    local reset_attempted, reset_complete, reset_err = default_reset.finish(
        self, category, complete, mod._gut_reset_modded_loadouts)
    if reset_attempted then
        _printf("[gut:1033] surface=standalone reset_complete=%s error=%s",
            tostring(reset_complete), tostring(reset_err or "none"))
    end
    self._dirty = self._dirty or count > 0
    self:_update_apply_button()
    self:_build_rows(category)
    if complete then self:_profile_capture(category) end
    _play_click()
    mod:debug("[mt:apply] pending buffer for '%s' complete=%s", tostring(key), tostring(complete))
end

-- (v0.2.148-dev) RESTORE DEFAULTS: stage every setting in the CURRENT tab back to its
-- default_value, then repaint the rows so the staged defaults show. This does NOT write
-- live — it STAGES (like a manual edit); the user clicks Apply to commit, at which point
-- apply_pending flushes the buffer through _cat_set. Because stage_set routes each edit to
-- its OWNER mod_id (_owner), the Equipment tab resets every member mod correctly.
-- Skips groups/headers (no setting_id), settings with no default_value, and keybinds
-- (type=="keybind", whose default_value is an empty table).
function ModTweakerView:reset_to_defaults()
    local category = self._build_category
    local n = default_reset.stage_defaults(self, category, self._build_nodes,
        _nf, DialogueUI.is_category)
    if n == nil then return end
    self:_update_apply_button()
    self:_build_rows(category)
    _play_click()
    mod:debug("[mt:reset] staged %d default(s) for '%s'", n, tostring(_cat_key(category)))
end

-- (Fix 3, v0.2.151-dev) Show the native "restore defaults" CONFIRM popup before resetting.
-- Rendered by the game's own Managers.popup (its own manager + renderer — no borrowed-renderer
-- issue), the same mechanism vanilla OptionsView uses for its reset/apply confirms
-- (options_view.lua:3335). queue_popup(text, topic, result_1, button_1, result_2, button_2);
-- query_result later returns the chosen result key. Only the CONFIRM ("reset_values") result
-- runs reset_to_defaults (current tab only). Falls back to an immediate reset if the popup
-- manager is unavailable, so the button never dead-ends.
function ModTweakerView:_queue_reset_popup()
    if self._dialogue_category then return end
    _play_click()
    if self._reset_popup_id then return end   -- already showing
    if not (Managers and Managers.popup and Managers.popup.queue_popup) then
        self:reset_to_defaults()
        return
    end
    -- Mirror the VANILLA reset-settings popup (options_view.lua:3335) VERBATIM: the engine
    -- Localizes popup text, so RAW English strings render as `<raw string>`. Real vanilla loc
    -- keys (reset_settings_popup_text / popup_discard_changes_topic / button_ok / popup_choice_cancel)
    -- resolve correctly. CONFIRM result = "reset_values"; cancel = "revert_changes".
    local ok, id = pcall(function()
        local text = Localize("reset_settings_popup_text")
        return Managers.popup:queue_popup(text, Localize("popup_discard_changes_topic"), "reset_values", Localize("button_ok"), "revert_changes", Localize("popup_choice_cancel"))
    end)
    if ok and id then self._reset_popup_id = id else self:reset_to_defaults() end
end

-- (Fix 3, v0.2.151-dev) Poll the reset-confirm popup each frame; run the reset ONLY on the
-- CONFIRM ("reset_values") result. Any other result (cancel / click-away) just dismisses.
function ModTweakerView:_check_reset_popup()
    local id = self._reset_popup_id
    if not id then return end
    if not (Managers and Managers.popup) then self._reset_popup_id = nil; return end
    local result = Managers.popup:query_result(id)
    if result then
        Managers.popup:cancel_popup(id)
        self._reset_popup_id = nil
        if result == "reset_values" then self:reset_to_defaults() end
    end
end

end

function M.bind_view_supplier(original_supplier, bind_catalog)
    local install_pending = install
    local function finish(status, ...)
        if not status or type((...)) ~= "table" then return status, ... end
        local class, binder = ...
        if type(binder) ~= "function" then return false, "private staged-view binder unavailable" end
        if type(bind_catalog) ~= "function" then return false, "private category catalog binder unavailable" end
        local bound, err = pcall(binder, install_pending, bind_catalog)
        if not bound then return false, err end
        return status, class, select(3, ...)
    end
    return function()
        return finish(original_supplier())
    end
end
return M
