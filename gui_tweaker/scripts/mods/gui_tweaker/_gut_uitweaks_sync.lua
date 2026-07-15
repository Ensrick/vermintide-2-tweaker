local mod = get_mod("gut")

-- ============================================================================
-- UI Tweaks (HideBuffs) HUD-customizer write-through (#312, phase 1)
-- ============================================================================
-- PROBLEM. gut's HUD customizer (_hud_customizer.lua) and the standalone Workshop
-- mod "UI Tweaks" (internal id "HideBuffs") BOTH reposition four shared HUD
-- elements: the buff bar, the boss health bar, the overcharge/heat bar, and the
-- energy bar. gut moves its registry scenegraph node; UI Tweaks moves a related
-- node/widget-offset EVERY frame inside its own hooks. With both configured the
-- offsets STACK (each mod nudges a different node in the same transform chain),
-- which is confusing and wrong. UI Tweaks also has NO in-game drag editor.
--
-- MODEL. When UI Tweaks is installed AND enabled AND gut's `gut_uitweaks_sync`
-- checkbox (default on) is set, UI Tweaks becomes the SINGLE OWNER of the four
-- elements: gut's drag editor writes UI Tweaks' offset settings instead of gut's
-- own per-resolution offsets, and gut pins its own registry node to the vanilla
-- baseline so it contributes nothing (see _hud_customizer.lua's owner-aware
-- apply/drag/reset branches). This module is a plain helper table (NO game hooks
-- of its own) exposing is_owned / get_offset / preview / commit / reset / migrate.
--
-- PER-ELEMENT VERIFICATION (decompiled VT2 + HideBuffs source, 2026-07-04). Every
-- mapped element's UI Tweaks apply site is an ADDITIVE offset in scenegraph UI
-- units (1080p reference, y-up: +x right, +y up), matching gut's cursor/drag space
-- (UIInverseScaleVectorToResolution + node.local_position). `node.position` and
-- `node.local_position` are the SAME table (ui_scenegraph.lua:82-83), so HB writing
-- `.position` == gut writing `.local_position`. So a write of gut's raw drag delta
-- {dx,dy} into the mapped UI Tweaks setting produces the same visual shift as gut's
-- own offset would. Details, with citations, per element:
--   * buff_ui  -> BUFFS_OFFSET_X/_Y. HB sets buff_pivot.position = {ox,oy} RAW
--     (buff_ui.lua:161-168). buff_pivot default is {0,0,1} (buff_ui_definitions.lua
--     :74-87), a child of the vanilla pivot chain, so RAW == delta. gut targets the
--     parent pivot_root {150,18} (REGISTRY). Same chain, same units/signs. COMPATIBLE.
--   * boss_health -> OTHER_ELEMENTS_BOSS_HP_BAR_OFFSET_X/_Y. HB sets
--     pivot.local_position = default(0,0) + offset (HideBuffs.lua:576-584). gut
--     targets the parent pivot_parent {0,-72}. Clean base+offset. COMPATIBLE.
--   * overcharge_bar -> OTHER_ELEMENTS_HEAT_BAR_OFFSET_X/_Y. HB sets the
--     charge_bar WIDGET .offset = {ox,oy} RAW (overcharge_bar.lua:4-11; widget
--     offset defaults {0,0,0}, y-up like scenegraph). gut targets the charge_bar
--     scenegraph node {0,-220}. Different field, same units/signs. COMPATIBLE.
--   * energy_bar -> OTHER_ENERGY_OFFSET_X/_Y. HB wraps
--     EnergyBarUI._apply_crosshair_position(x,y) -> func(x+ox, y+oy)
--     (HideBuffs.lua:457-463), which writes screen_bottom_pivot.local_position
--     (energy_bar_ui.lua:133-139). gut's node charge_bar {0,-220} is a CHILD of
--     screen_bottom_pivot (energy_bar_ui_definitions), so it inherits the shift.
--     The "base" is the dynamic crosshair position, but the offset is purely
--     additive in the same y-up scenegraph units. COMPATIBLE, with a caveat: the
--     energy bar follows the crosshair and only redraws when dirty, so a live drag
--     preview can lag (pre-existing to gut's own energy handling; the committed
--     value is always correct).
--
-- No element was excluded: all four verified as additive offsets in the same
-- coordinate space with matching signs (verified, not guessed).

-- customizer widget id -> the HideBuffs SETTING_NAMES *keys* for its x/y offset.
-- (HB.SETTING_NAMES maps each key to the real setting_id string; we resolve through
-- it in _sid so we never assume key == setting_id.)
local ELEMENT_MAP = {
    buff_ui        = { x = "BUFFS_OFFSET_X",                       y = "BUFFS_OFFSET_Y" },
    boss_health    = { x = "OTHER_ELEMENTS_BOSS_HP_BAR_OFFSET_X",  y = "OTHER_ELEMENTS_BOSS_HP_BAR_OFFSET_Y" },
    overcharge_bar = { x = "OTHER_ELEMENTS_HEAT_BAR_OFFSET_X",     y = "OTHER_ELEMENTS_HEAT_BAR_OFFSET_Y" },
    energy_bar     = { x = "OTHER_ENERGY_OFFSET_X",                y = "OTHER_ENERGY_OFFSET_Y" },
}

local M = { ELEMENT_MAP = ELEMENT_MAP }

-- Resolve a HideBuffs setting_id from a SETTING_NAMES key (nil if HB or the key is
-- missing). SETTING_NAMES maps KEY -> setting_id string.
local function _sid(HB, setting_key)
    local names = HB and HB.SETTING_NAMES
    return names and names[setting_key]
end

-- Durable flush of the shared VMF settings store. VMFMod.set writes into a single
-- module-level _mods_settings table (shared across ALL mods) and flips a shared
-- unsaved flag; save_unsaved_settings_to_file() -> Application.set_user_setting +
-- save_user_settings() (VMF core/settings.lua:5-55). So gut can durably persist a
-- foreign mod's settings after HB:set. Verified against the VMF source.
local function _save_durable()
    local vmf = get_mod("VMF")
    if vmf and type(vmf.save_unsaved_settings_to_file) == "function" then
        pcall(vmf.save_unsaved_settings_to_file)
    end
end

-- True iff UI Tweaks should own `widget_id`: it is a mapped element, gut's sync
-- toggle is on, HideBuffs is installed AND enabled, and it exposes the mapped
-- setting keys. Total no-op (false) otherwise, so gut keeps owning its own offsets.
function M.is_owned(widget_id)
    if not ELEMENT_MAP[widget_id] then return false end
    if not mod:get("gut_uitweaks_sync") then return false end
    local HB = get_mod("HideBuffs")
    if not HB then return false end
    -- mod:is_enabled() is a VMF mod method (core/toggling.lua). Guard the call in
    -- case a future VMF drops it; treat an unreadable result as "enabled" so a
    -- present-but-uncheckable HB still owns (better than silently double-applying).
    if type(HB.is_enabled) == "function" then
        local ok, enabled = pcall(HB.is_enabled, HB)
        if ok and enabled == false then return false end
    end
    local m = ELEMENT_MAP[widget_id]
    return (_sid(HB, m.x) ~= nil) and (_sid(HB, m.y) ~= nil)
end

-- Current UI Tweaks offset for `widget_id` (0,0 if unavailable). Used by the drag
-- editor to anchor a drag at the element's existing position.
function M.get_offset(widget_id)
    local HB = get_mod("HideBuffs")
    local m = ELEMENT_MAP[widget_id]
    if not (HB and m) then return 0, 0 end
    local xid, yid = _sid(HB, m.x), _sid(HB, m.y)
    local x = xid and HB:get(xid) or 0
    local y = yid and HB:get(yid) or 0
    return tonumber(x) or 0, tonumber(y) or 0
end

-- During-drag write. notify=false: a cheap in-memory write; UI Tweaks re-reads the
-- value inside its own per-frame hooks and redraws next frame. No durable save.
function M.preview(widget_id, dx, dy)
    local HB = get_mod("HideBuffs")
    local m = ELEMENT_MAP[widget_id]
    if not (HB and m) then return end
    local xid, yid = _sid(HB, m.x), _sid(HB, m.y)
    if not (xid and yid) then return end
    pcall(HB.set, HB, xid, dx, false)
    pcall(HB.set, HB, yid, dy, false)
end

-- Mouse-release commit. notify=true fires HB.on_setting_changed (its re-layout
-- dirty flags, e.g. mod_events.lua:136), then a durable VMF settings flush.
function M.commit(widget_id, dx, dy)
    local HB = get_mod("HideBuffs")
    local m = ELEMENT_MAP[widget_id]
    if not (HB and m) then return end
    local xid, yid = _sid(HB, m.x), _sid(HB, m.y)
    if not (xid and yid) then return end
    pcall(HB.set, HB, xid, dx, true)
    pcall(HB.set, HB, yid, dy, true)
    _save_durable()
end

-- Reset: zero UI Tweaks' offset for the element (back to vanilla) + notify + save.
function M.reset(widget_id)
    local HB = get_mod("HideBuffs")
    local m = ELEMENT_MAP[widget_id]
    if not (HB and m) then return end
    local xid, yid = _sid(HB, m.x), _sid(HB, m.y)
    if not (xid and yid) then return end
    pcall(HB.set, HB, xid, 0, true)
    pcall(HB.set, HB, yid, 0, true)
    _save_durable()
end

-- One-time migration: for each mapped element with a NON-ZERO stored gut offset at
-- the CURRENT resolution, fold that delta ADDITIVELY into UI Tweaks' offset (so the
-- element keeps its current on-screen position once gut stops applying its own
-- offset), then zero gut's stored offset. Idempotent (guard flag + zero-offset
-- no-op). No-op when HideBuffs is absent or sync is off (retried later).
local _migrated = false
function M.migrate()
    if _migrated then return end
    local HB = get_mod("HideBuffs")
    if not HB then return end                       -- HB not loaded yet: retry at on_all_mods_loaded
    if not mod:get("gut_uitweaks_sync") then return end  -- sync off: gut still owns its offsets
    local cust = mod._gut_hud_customizer
    if not cust or type(cust.get_widget_offset) ~= "function" then return end

    local folded = 0
    for widget_id, m in pairs(ELEMENT_MAP) do
        local gdx, gdy = cust.get_widget_offset(widget_id)
        gdx, gdy = tonumber(gdx) or 0, tonumber(gdy) or 0
        if gdx ~= 0 or gdy ~= 0 then
            local xid, yid = _sid(HB, m.x), _sid(HB, m.y)
            if xid and yid then
                local hx = tonumber(HB:get(xid)) or 0
                local hy = tonumber(HB:get(yid)) or 0
                pcall(HB.set, HB, xid, hx + gdx, true)
                pcall(HB.set, HB, yid, hy + gdy, true)
                if type(cust.clear_widget_offset) == "function" then
                    pcall(cust.clear_widget_offset, widget_id)
                end
                folded = folded + 1
            end
        end
    end
    if folded > 0 then _save_durable() end
    _migrated = true
    printf("[gut:uitweaks_sync] migrate: folded %d gut HUD offset(s) into UI Tweaks", folded)
end

-- Publish for the customizer (resolves mod._gut_uitweaks_sync at call time) and for
-- the regression test (reads M.ELEMENT_MAP). Then attempt the one-time migrate now
-- (no-op if HB absent or sync off; re-attempted at on_all_mods_loaded).
function M.install()
    mod._gut_uitweaks_sync = M
    pcall(M.migrate)
    return true
end

mod._gut_uitweaks_sync = M

return M
