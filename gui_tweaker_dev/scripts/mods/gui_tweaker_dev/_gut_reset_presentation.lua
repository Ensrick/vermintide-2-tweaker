-- _gut_reset_presentation.lua -- active-career presentation reconcile after an
-- Equipment DEFAULT reset (issue #1033).
--
-- The persistence half of #1033 (reset_modded_loadouts in _gut_native_loadouts.lua)
-- rewrites the modded store and dirtifies the backend interfaces, but the live unit
-- keeps its already-spawned weapons/attachments/skin, so the lobby model rendered
-- stale (Rain 2026-08-03 log: `[gut:1033] ... writes=2 dirtify=1` + reset_complete=true
-- with a stale model). This module performs ONE bounded reconcile of the ACTIVE career
-- after the reset transaction: a skin ownership change requests one vanilla profile
-- respawn (the exact skin-sync path, hero_view_state_overview.lua:1157-1161 ->
-- ingame_ui.lua:1290-1305), any other changed live slot re-equips through the exact
-- vanilla presentation calls the hero-view equip request makes
-- (SimpleInventoryExtension.create_equipment_in_slot, simple_inventory_extension.lua:1372;
-- PlayerUnitAttachmentExtension.create_attachment_in_slot,
-- player_unit_attachment_extension.lua:241; dispatch shape hero_view_state_overview.lua:697-714).
-- Mission-side, or when no live unit is ready, the reset stays durable and the
-- reconcile DEFERS to the next safe keep boundary: a chained mod.update consumes the
-- pending intent once the keep unit is alive, where the residual diff is normally 0
-- because the keep spawn itself consumed the reseeded rows (fallback 3 probe,
-- issue #1033 comments).
--
-- NO NEW HOOK (NON-NEGOTIABLE 8): engine access is plain reads, the two vanilla
-- extension calls, and one IngameUI:respawn, driven by the reset owner plus a chained
-- mod.update -- pre-flight grep 2026-08-15: gut installs no hook on
-- SimpleInventoryExtension, PlayerUnitAttachmentExtension, or IngameUI. Desired values
-- are read via BackendUtils AFTER the reset dirtified the interfaces -- a command-context
-- read, NOT a mirror-read hook, so the v0.2.173 get_item_from_id recursion is
-- structurally impossible here (same safety exit_snapshot and /gut_loadout_status rely
-- on). Keep detection reads DamageUtils.is_in_inn (published by state_ingame.lua:135-137
-- from the hub_level setting; gut's mission modules already treat it as the reliable
-- keep signal). Every receipt is a bounded [gut:1033] printf per reset event, never
-- per frame; the chained update early-outs on two file-local nils.
--
-- Owned by: gui_tweaker_dev.lua entry point. Consumed via: mod:dofile (single call);
-- the reset owner reaches it lazily through mod._gut_reset_presentation.

local mod = get_mod("gut_dev")
local Core = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_reset_presentation_core")

local M = { core = Core }

local _pending = nil        -- deferred reconcile intent: { source }
local _await = nil          -- post-respawn verify: { source, career, old_unit, t }
local AWAIT_TIMEOUT = 10    -- seconds before the post-respawn verify reports timeout

local function _printf(fmt, ...)
    pcall(printf, fmt, ...)
end

local function _in_keep()
    local du = rawget(_G, "DamageUtils")
    return du ~= nil and du.is_in_inn == true
end

-- Active local player + career + live unit. Any failure reads as "not ready".
local function _active_player()
    local ok, player = pcall(function() return Managers.player:local_player() end)
    if not ok or not player then return nil end
    local ok_c, career = pcall(function() return player:career_name() end)
    local unit = player.player_unit
    local alive_lookup = rawget(_G, "ALIVE")
    local alive = unit ~= nil and alive_lookup ~= nil and alive_lookup[unit] == true
    return player, (ok_c and career) or nil, unit, alive
end

-- Canonical skin identity for the career, read through the backend (post-dirtify this
-- is the reset's truth; pre-reset it is the store/overlay truth). Same identity shape
-- the store captures (Policy.canonical_equip_value: override_id or ItemId).
local function _skin_value(career_name)
    local BU = rawget(_G, "BackendUtils")
    if not (BU and BU.get_loadout_item) then return nil end
    local ok, item = pcall(BU.get_loadout_item, career_name, "slot_skin", false)
    if not ok or type(item) ~= "table" then return nil end
    local v = item.override_id or item.ItemId
    return type(v) == "string" and v or nil
end

-- Desired backend ids over the equip slots: the exact reader vanilla's spawn/equip
-- flow consults (BackendUtils.get_loadout_item_id, backend_utils.lua:14-20).
local function _desired_ids(career_name)
    local BU = rawget(_G, "BackendUtils")
    local out = {}
    if not (BU and BU.get_loadout_item_id) then return out end
    for i = 1, #Core.EQUIP_SLOTS do
        local slot = Core.EQUIP_SLOTS[i]
        local ok, id = pcall(BU.get_loadout_item_id, career_name, slot, false)
        if ok and id ~= nil then out[slot] = id end
    end
    return out
end

-- Masterlist item names for the desired ids. nil = unresolvable right now = the plan
-- SKIPS that slot (non-destructive doctrine); also exactly what create_*_in_slot
-- would fail to resolve (both go through get_item_from_masterlist).
local function _desired_keys(desired)
    local BU = rawget(_G, "BackendUtils")
    local keys = {}
    if not (BU and BU.get_item_from_masterlist) then return keys end
    for slot, id in pairs(desired) do
        local ok, item_data = pcall(BU.get_item_from_masterlist, id)
        if ok and type(item_data) == "table" then
            keys[slot] = item_data.name or item_data.key
        end
    end
    return keys
end

-- What the unit is ACTUALLY presenting right now, per extension slot data
-- (simple_inventory_extension.lua:1343; player_unit_attachment_extension.lua:186).
local function _live_values(unit)
    local live_id, live_key = {}, {}
    local inv = ScriptUnit.extension(unit, "inventory_system")
    local att = ScriptUnit.extension(unit, "attachment_system")
    for i = 1, #Core.EQUIP_SLOTS do
        local slot = Core.EQUIP_SLOTS[i]
        local ext = Core.SLOT_ROUTES[slot] == Core.ROUTE_INVENTORY and inv or att
        if ext and ext.get_slot_data then
            local ok, slot_data = pcall(ext.get_slot_data, ext, slot)
            local item_data = ok and type(slot_data) == "table" and slot_data.item_data or nil
            if type(item_data) == "table" then
                live_id[slot] = item_data.backend_id
                live_key[slot] = item_data.name or item_data.key
            end
        end
    end
    return live_id, live_key
end

local function _slot_report(ids, keys)
    local parts = {}
    for i = 1, #Core.EQUIP_SLOTS do
        local slot = Core.EQUIP_SLOTS[i]
        parts[#parts + 1] = string.format("%s=%s/%s",
            (slot:gsub("^slot_", "")), tostring(ids[slot]), tostring(keys[slot]))
    end
    return table.concat(parts, " ")
end

-- One vanilla profile respawn via the live IngameUI (captured by _ba_heroview_inject;
-- fresh in the keep because HeroView.init re-captures on every hero-view open).
-- IngameUI.respawn itself no-ops without a network game (ingame_ui.lua:1291-1295).
local function _request_respawn()
    return pcall(function()
        local ctx = mod._gut_ingame_ui_context
        local ingame_ui = ctx and ctx.ingame_ui
        assert(type(ingame_ui) == "table" and type(ingame_ui.respawn) == "function",
            "ingame_ui unavailable")
        ingame_ui:respawn()
    end)
end

local function _apply_equip(unit, slot_name, backend_id, route)
    return pcall(function()
        if route == Core.ROUTE_INVENTORY then
            local ext = ScriptUnit.extension(unit, "inventory_system")
            ext:create_equipment_in_slot(slot_name, backend_id)
        else
            local ext = ScriptUnit.extension(unit, "attachment_system")
            ext:create_attachment_in_slot(slot_name, backend_id)
        end
    end)
end

-- Pre-reset capture: the reset owner calls this BEFORE clearing the store so the
-- reconcile can detect a skin ownership change (pre-reset backend truth vs post-reset
-- backend truth). Pure reads; never mutates anything.
function M.capture_before()
    local _, career = _active_player()
    if not career then return nil end
    return {
        career_name = career,
        skin_before = _skin_value(career),
    }
end

-- One bounded active-career presentation reconcile. Called by the reset owner AFTER
-- the persistence transaction (+_dirtify). Returns a short outcome string for logs.
function M.reconcile(before_ctx, source)
    local _, career, unit, alive = _active_player()
    if not career then
        _printf("[gut:1033] reconcile source=%s SKIP (no active local career)", tostring(source))
        return "skip"
    end
    local in_keep = _in_keep()
    if Core.should_defer(in_keep, alive) then
        _pending = { source = tostring(source) }
        _printf("[gut:1033] reconcile source=%s career=%s DEFERRED to next safe keep boundary (in_keep=%s unit_alive=%s); reset stays durable",
            tostring(source), tostring(career), tostring(in_keep), tostring(alive))
        return "deferred"
    end

    local desired = _desired_ids(career)
    local desired_keys = _desired_keys(desired)
    local live_id, live_key = _live_values(unit)
    local skin_after = _skin_value(career)
    local skin_before = (before_ctx and before_ctx.career_name == career)
        and before_ctx.skin_before or nil
    local row = before_ctx and before_ctx.selected_row

    -- Fallback-1 receipt: active career, selected row, desired backend ids, live
    -- inventory/attachment identities -- BEFORE any presentation action.
    _printf("[gut:1033] reconcile-before source=%s career=%s row=%s skin=%s->%s desired[%s] live[%s]",
        tostring(source), tostring(career), tostring(row),
        tostring(skin_before), tostring(skin_after),
        _slot_report(desired, desired_keys), _slot_report(live_id, live_key))

    if Core.skin_changed(skin_before, skin_after) then
        local ok_r = _request_respawn()
        if ok_r then
            -- Verify receipt lands once the NEW unit is alive (chained update below).
            _await = { source = tostring(source), career = career, old_unit = unit, t = 0 }
            _printf("[gut:1033] reconcile source=%s career=%s skin ownership changed -> one profile respawn requested (ingame_ui.respawn)",
                tostring(source), tostring(career))
            return "respawn"
        end
        -- Respawn lever unavailable: keep the durable reset, defer to the next safe
        -- keep boundary (fallback 3) instead of leaving the stale model unaccounted.
        _pending = { source = tostring(source) }
        _printf("[gut:1033] reconcile source=%s career=%s skin changed but respawn UNAVAILABLE -> deferred to next safe keep boundary",
            tostring(source), tostring(career))
        return "respawn-deferred"
    end

    local plan = Core.plan(desired, desired_keys, live_id, live_key)
    local equipped, failed = 0, 0
    for i = 1, #plan.actions do
        local a = plan.actions[i]
        local ok_e = _apply_equip(unit, a.slot, a.backend_id, a.route)
        if ok_e then equipped = equipped + 1 else failed = failed + 1 end
        _printf("[gut:1033] reconcile-equip slot=%s id=%s route=%s ok=%s",
            a.slot, tostring(a.backend_id), a.route, tostring(ok_e))
    end
    _printf("[gut:1033] reconcile-after source=%s career=%s equips=%d failed=%d skipped_same=%d skipped_unresolvable=%d skipped_empty=%d respawn=false",
        tostring(source), tostring(career), equipped, failed,
        plan.skipped_same, plan.skipped_unresolvable, plan.skipped_empty)
    return "equipped"
end

-- Deferred-intent + post-respawn-verify pump. Only runs while an intent is armed
-- (the chained update below early-outs otherwise). One-shot per intent; any raise
-- clears the intents so a broken state can never spam.
function M.update(dt)
    local ok = pcall(function()
        if _await then
            _await.t = (_await.t or 0) + (tonumber(dt) or 0)
            local _, career, unit, alive = _active_player()
            if alive and unit ~= _await.old_unit and career == _await.career then
                local desired = _desired_ids(career)
                local desired_keys = _desired_keys(desired)
                local live_id, live_key = _live_values(unit)
                local plan = Core.plan(desired, desired_keys, live_id, live_key)
                _printf("[gut:1033] reconcile-verify source=%s career=%s residual=%d live[%s] (respawned unit consumed the reseeded rows=%s)",
                    tostring(_await.source), tostring(career), #plan.actions,
                    _slot_report(live_id, live_key), tostring(#plan.actions == 0))
                _await = nil
            elseif _await.t > AWAIT_TIMEOUT then
                _printf("[gut:1033] reconcile-verify source=%s TIMEOUT after %ds (respawn produced no new live unit)",
                    tostring(_await.source), AWAIT_TIMEOUT)
                _await = nil
            end
        end
        if _pending and _in_keep() then
            local _, career, unit, alive = _active_player()
            if career and alive then
                local src = _pending.source
                _pending = nil
                -- Keep boundary reached: the spawn consumed the reseeded rows; this
                -- diff-based pass proves it (residual 0) or repairs any residue.
                M.reconcile(nil, src .. "_deferred")
            end
        end
    end)
    if not ok then
        _pending, _await = nil, nil
    end
end

-- Test-only visibility (rt checks); never consumed by the reconcile itself.
function M.pending_state()
    return _pending ~= nil, _await ~= nil
end

-- Chained VMF lifecycle callback (same idiom as _gut_camera/_gut_freecam), NOT an
-- engine hook. Per-frame cost is two file-local nil reads unless an intent is armed.
local _gut_reset_presentation_prev_update = mod.update
mod.update = function(dt)
    if _gut_reset_presentation_prev_update then _gut_reset_presentation_prev_update(dt) end
    if _pending == nil and _await == nil then return end
    M.update(dt)
end

M.rt_checks = {
    { name = "issue1033_presentation_reconcile_plan", fn = function()
        if type(M.reconcile) ~= "function" or type(M.capture_before) ~= "function"
            or type(M.update) ~= "function" then
            return "reconcile surface missing"
        end
        if mod._gut_reset_presentation ~= M then return "mod namespace not published" end
        -- Route partition must mirror the vanilla dispatch: weapons ride inventory,
        -- hat+jewelry ride attachment, skin is the respawn lever, frame/pose are
        -- backend-only surfaces.
        local want = {
            slot_melee = "inventory", slot_ranged = "inventory",
            slot_hat = "attachment", slot_necklace = "attachment",
            slot_ring = "attachment", slot_trinket_1 = "attachment",
            slot_skin = "respawn", slot_frame = "none", slot_pose = "none",
        }
        for slot, route in pairs(want) do
            if Core.SLOT_ROUTES[slot] ~= route then
                return "route drift for " .. slot .. ": " .. tostring(Core.SLOT_ROUTES[slot])
            end
        end
        for slot in pairs(Core.SLOT_ROUTES) do
            if want[slot] == nil then return "unknown routed slot " .. slot end
        end
        -- Behavioral: a reset that changed melee+hat plans exactly those two equips;
        -- an identical live state plans zero; an unresolvable desired id is skipped.
        local desired = { slot_melee = "IDM", slot_ranged = "IDR", slot_hat = "IDH" }
        local keys = { slot_melee = "k_m", slot_ranged = "k_r", slot_hat = "k_h" }
        local plan = Core.plan(desired, keys,
            { slot_melee = "OLD", slot_ranged = "IDR", slot_hat = "OLDH" }, {})
        if #plan.actions ~= 2 then return "expected 2 planned equips, got " .. #plan.actions end
        if plan.actions[1].slot ~= "slot_melee" or plan.actions[1].route ~= "inventory" then
            return "melee action misrouted"
        end
        if plan.actions[2].slot ~= "slot_hat" or plan.actions[2].route ~= "attachment" then
            return "hat action misrouted"
        end
        local clean = Core.plan(desired, keys,
            { slot_melee = "IDM", slot_ranged = "IDR", slot_hat = "IDH" }, {})
        if #clean.actions ~= 0 then return "identical live state must plan zero equips" end
        local unresolved = Core.plan({ slot_melee = "IDX" }, {}, {}, {})
        if #unresolved.actions ~= 0 or unresolved.skipped_unresolvable ~= 1 then
            return "unresolvable desired id must be skipped, never equipped"
        end
        if not Core.skin_changed("a", "b") or Core.skin_changed("a", "a")
            or Core.skin_changed(nil, "b") or Core.skin_changed("a", nil) then
            return "skin-change predicate wrong"
        end
        if not Core.should_defer(false, true) or not Core.should_defer(true, false)
            or Core.should_defer(true, true) then
            return "defer predicate wrong"
        end
    end },
}

mod._gut_reset_presentation = M

return M
