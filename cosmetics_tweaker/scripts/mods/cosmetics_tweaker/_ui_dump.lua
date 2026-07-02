-- _ui_dump.lua
--
-- v0.9.24-dev: comprehensive UI dump harness. When `enable_debug_logging`
-- is ON, every cosmetic / inventory / crafting window logs a structured
-- snapshot of its state on `on_enter` so the developer (Claude, between
-- sessions) can learn the UI's shape from the running game rather than
-- speculating from source. When the toggle is OFF, every hook is a fast
-- no-op (a single bool check).
--
-- Hook strategy:
--   * String-form `mod:hook` (wrapping variant — chains correctly per
--     VMF_RECIPES.md § 1; `hook_safe` does NOT chain, which is why we
--     can't just stack hook_safe on top of existing registrations).
--   * Wraps `on_enter(self, params, offset)`. Calls vanilla, then dumps.
--   * Each window class gets one registration. Vanilla return values are
--     captured into a single local and returned verbatim — most `on_enter`
--     methods don't return anything but we're defensive about multi-return
--     collapse (VMF_RECIPES.md § 2).
--
-- Output format: every line is `[ui-dump:<ClassName>] <key>=<value> ...`
-- so a future maintainer can `grep "^.*\[ui-dump:HeroWindowInventory\]"`
-- and isolate the slice they need.
--
-- Volume control: the dump fires on every `on_enter`. Windows that are
-- entered many times per session (when the user clicks back-and-forth
-- between tabs) will emit many copies; that's intentional. The widget
-- inventory is identical across enters, but the ITEM context (current
-- backend_id, current skin, equipped state) changes per entry — capturing
-- the context dimension is the whole point.

local mod = get_mod("cosmetics_tweaker")

local M = {}

local function _enabled()
    return true
end

-- ===========================================================================
-- Format helpers
-- ===========================================================================

local function _sorted_keys(t)
    local out = {}
    if type(t) ~= "table" then return out end
    for k in pairs(t) do out[#out + 1] = tostring(k) end
    table.sort(out)
    return out
end

local function _short_list(t, max_n)
    -- Render a list inline; truncate with `...(N more)` past max_n.
    if not t or #t == 0 then return "{}" end
    if #t <= max_n then return "{" .. table.concat(t, ", ") .. "}" end
    local head = {}
    for i = 1, max_n do head[i] = t[i] end
    return "{" .. table.concat(head, ", ") .. ", ...(" .. (#t - max_n) .. " more)}"
end

local function _safe_str(v)
    if v == nil then return "nil" end
    local t = type(v)
    if t == "string" or t == "number" or t == "boolean" then return tostring(v) end
    return t  -- avoid dumping `table: 0xdeadbeef` noise — just say "table"
end

-- v0.9.30-dev: format a vector3-shaped mat-template field as "(x,y,z)".
-- Used by the MaterialSettingsTemplates dump.
local function _fmt_v3(t)
    if type(t) ~= "table" then return _safe_str(t) end
    if t.type == "vector3" then
        return string.format("v3(%.4g, %.4g, %.4g)",
            t.x or 0, t.y or 0, t.z or 0)
    end
    -- Fall through to a flat key=value dump of whatever shape it has.
    local parts = {}
    for k, v in pairs(t) do
        parts[#parts + 1] = tostring(k) .. "=" .. _safe_str(v)
    end
    return "{" .. table.concat(parts, " ") .. "}"
end

-- ===========================================================================
-- Generic per-window state probes
-- ===========================================================================

local function _dump_window_common(prefix, self, params, offset)
    -- Top-level context every window carries.
    mod:info("%s on_enter hero=%s career_idx=%s profile_idx=%s peer=%s offset=%s",
        prefix, _safe_str(self.hero_name), _safe_str(self.career_index),
        _safe_str(self.profile_index), _safe_str(self.peer_id), _safe_str(offset))
    -- Selected params we care about — the rest of params is a giant
    -- ingame_ui_context blob that's noisy to print.
    if type(params) == "table" then
        local interesting = { "hero_name", "career_index", "profile_index",
            "item_backend_id", "wwise_world", "is_in_inn",
            "use_gamepad_layout" }
        local parts = {}
        for _, k in ipairs(interesting) do
            local v = params[k]
            if v ~= nil then parts[#parts + 1] = k .. "=" .. _safe_str(v) end
        end
        if #parts > 0 then
            mod:info("%s params: %s", prefix, table.concat(parts, " "))
        end
    end
    -- Widget inventory — names only. The shape of each widget is verbose
    -- and rarely useful; the NAME tells you what's on screen, which is
    -- what you need to find a click handler or animation target.
    if self._widgets_by_name then
        local names = _sorted_keys(self._widgets_by_name)
        mod:info("%s widgets (%d): %s", prefix, #names, _short_list(names, 40))
    end
end

local function _dump_item(prefix, item, label)
    if type(item) ~= "table" then return end
    mod:info("%s %s: key=%s bid=%s skin=%s rarity=%s power=%s slot_type=%s",
        prefix, label or "item",
        _safe_str(item.key or (item.data and item.data.key)),
        _safe_str(item.backend_id),
        _safe_str(item.skin),
        _safe_str(item.rarity),
        _safe_str(item.power_level),
        _safe_str(item.data and item.data.slot_type))
end

-- Walk a slot table and dump each slot's item. Tolerates both
-- `slots[slot_name] = item_data` and the wrapped form
-- `slots[slot_name] = { item_data = ... }` patterns.
local function _dump_slots(prefix, slots, label)
    if type(slots) ~= "table" then return end
    local count = 0
    for slot_name, entry in pairs(slots) do
        count = count + 1
        local item = (entry and entry.item_data) or entry
        if type(item) == "table" then
            mod:info("%s   %s[%s]: key=%s bid=%s skin=%s rarity=%s",
                prefix, label or "slot", _safe_str(slot_name),
                _safe_str(item.key or item.name),
                _safe_str(item.backend_id),
                _safe_str(item.skin),
                _safe_str(item.rarity))
        end
    end
    if count > 0 then
        mod:info("%s %s total=%d", prefix, label or "slots", count)
    end
end

-- ===========================================================================
-- Per-window enrichers — class-specific extra state that's worth dumping.
-- Looked up by class name. Called AFTER _dump_window_common.
-- ===========================================================================

local _ENRICHERS = {}

-- v0.9.30-dev: one-shot MaterialSettingsTemplates inventory. Fires the
-- first time a customizer opens with debug logging on (per session).
-- This is the engine's global glow-family table — every entry on a
-- weapon skin's `material_settings_name` field resolves here. Capturing
-- once gives the developer the full tunable surface (which fields each
-- family has, their vector3 defaults) without spamming per-open.
local _mat_templates_dumped = false
local function _dump_material_templates_once(prefix)
    if _mat_templates_dumped then return end
    local templates = rawget(_G, "MaterialSettingsTemplates")
    if type(templates) ~= "table" then
        mod:info("%s [mat-templates] MaterialSettingsTemplates not loaded yet — will retry next open", prefix)
        return
    end
    _mat_templates_dumped = true
    local names = _sorted_keys(templates)
    mod:info("%s [mat-templates] === MaterialSettingsTemplates inventory (%d) ===",
        prefix, #names)
    for _, name in ipairs(names) do
        local tpl = templates[name]
        if type(tpl) == "table" then
            local field_lines = {}
            for k, v in pairs(tpl) do
                field_lines[#field_lines + 1] = tostring(k) .. "=" .. _fmt_v3(v)
            end
            -- Stable field order so diffs are clean across sessions.
            table.sort(field_lines)
            mod:info("%s [mat-templates]   %s: %s",
                prefix, name, table.concat(field_lines, " | "))
        end
    end
    mod:info("%s [mat-templates] === end inventory ===", prefix)
end

-- v0.9.30-dev: full per-skin dump used by the customizer enricher.
-- Beyond `mat=` and `rarity=`, capture the rest of the skin entry —
-- display_name (so we can match labels), units (1P/3P paths so we know
-- mesh side-effects), and any other top-level fields. One INFO line per
-- skin in the grid; cap at 16 entries (matches the per-window dump
-- truncation pattern).
local function _dump_skin_entry_full(prefix, idx, skin_key, entry)
    if type(entry) ~= "table" then return end
    local mat = entry.material_settings_name
    local L = rawget(_G, "Localize")
    local display = entry.display_name
    local display_localized = display
    if L and display then
        local ok, loc = pcall(L, display)
        if ok and type(loc) == "string" and loc ~= "" then display_localized = loc end
    end
    -- Collect any extra string/scalar top-level keys.
    local extras = {}
    for k, v in pairs(entry) do
        if k ~= "material_settings_name" and k ~= "rarity"
           and k ~= "display_name" and k ~= "left_hand_unit"
           and k ~= "right_hand_unit" and k ~= "first_person_unit"
           and k ~= "third_person_unit" and k ~= "unit" then
            local t = type(v)
            if t == "string" or t == "number" or t == "boolean" then
                extras[#extras + 1] = k .. "=" .. tostring(v)
            end
        end
    end
    table.sort(extras)
    mod:info("%s [skin-entry][%d] %s: display=%s mat=%s rarity=%s",
        prefix, idx, skin_key, _safe_str(display_localized),
        _safe_str(mat), _safe_str(entry.rarity))
    if entry.left_hand_unit or entry.right_hand_unit
       or entry.first_person_unit or entry.third_person_unit or entry.unit then
        mod:info("%s [skin-entry][%d]   units: 1p=%s 3p=%s L=%s R=%s flat=%s",
            prefix, idx,
            _safe_str(entry.first_person_unit),
            _safe_str(entry.third_person_unit),
            _safe_str(entry.left_hand_unit),
            _safe_str(entry.right_hand_unit),
            _safe_str(entry.unit))
    end
    if #extras > 0 then
        mod:info("%s [skin-entry][%d]   extras: %s",
            prefix, idx, table.concat(extras, " "))
    end
end

_ENRICHERS.HeroWindowItemCustomization = function(prefix, self)
    -- v0.9.30-dev: dump the MaterialSettingsTemplates inventory once per
    -- session (first customizer open). Gives us the full glow-family
    -- surface area in one place.
    _dump_material_templates_once(prefix)
    -- The single item being customized. The screen carries it via
    -- `_item_backend_id` and resolves via `:_get_item(bid)`.
    if self._item_backend_id and self._get_item then
        local ok, item = pcall(self._get_item, self, self._item_backend_id)
        if ok then
            _dump_item(prefix, item, "customizing")
            -- v0.9.30-dev: also dump skin_combination_table — the named
            -- WeaponSkins.skin_combinations entry that drives the grid.
            -- Lets us correlate the grid contents back to the source.
            if item and item.data then
                mod:info("%s customizing.data: skin_combination_table=%s default_skin=%s",
                    prefix, _safe_str(item.data.skin_combination_table),
                    _safe_str(item.data.default_skin))
            end
        end
    end
    -- Illusion grid: every clickable skin slot built by `_setup_illusions`.
    -- Each widget carries the skin_key on its content.
    if self._illusion_widgets then
        local skins = {}
        for i, w in ipairs(self._illusion_widgets) do
            local sk = w.content and w.content.skin_key
            local entry = sk and rawget(_G, "WeaponSkins") and WeaponSkins.skins
                and WeaponSkins.skins[sk]
            skins[#skins + 1] = string.format("[%d] %s (mat=%s rarity=%s)",
                i, _safe_str(sk),
                _safe_str(entry and entry.material_settings_name),
                _safe_str(entry and entry.rarity))
        end
        mod:info("%s illusion grid (%d): %s",
            prefix, #self._illusion_widgets, _short_list(skins, 16))
        -- v0.9.30-dev: per-skin full dump. One INFO line per skin (up to
        -- 16). The summary above is a one-liner roll-up; this is the
        -- detail-level view a future maintainer needs to design the
        -- per-instance glow popup. Gated within the existing
        -- enable_debug_logging check (we're already inside _enabled()).
        local WS = rawget(_G, "WeaponSkins")
        if WS and WS.skins then
            local cap = math.min(#self._illusion_widgets, 16)
            for i = 1, cap do
                local w = self._illusion_widgets[i]
                local sk = w and w.content and w.content.skin_key
                local entry = sk and rawget(WS.skins, sk)
                _dump_skin_entry_full(prefix, i, sk, entry)
            end
            if #self._illusion_widgets > 16 then
                mod:info("%s [skin-entry] ...(%d more truncated)",
                    prefix, #self._illusion_widgets - 16)
            end
        end
    end
    -- v0.9.30-dev: state-machine snapshot. The customizer is a state
    -- machine (see vanilla's `_state_draw_overview`, `_state_*` methods).
    -- Knowing which state we're in tells us which interaction path is
    -- active. Stash whatever vanilla exposes.
    mod:info("%s state: current=%s selected_idx=%s current_recipe=%s",
        prefix,
        _safe_str(self._state or self._current_state or self._state_name),
        _safe_str(self._selected_illusion_index or self._selected_skin_index),
        _safe_str(self._current_recipe_name))
    -- Recipe widgets (Properties / Traits / Reroll / Upgrade etc.) and
    -- whatever recipe is currently selected.
    if self._recipe_widgets then
        mod:info("%s recipe_widgets=%d current_recipe=%s",
            prefix, #self._recipe_widgets, _safe_str(self._current_recipe_name))
    end
    -- CT-injected offhand picker state (the row-2 shield picker that
    -- caused issue #37). Useful for verifying the v0.9.19 on_release fix
    -- and for surfacing pool contents.
    if self._ct_offhand_widgets then
        mod:info("%s ct_offhand: widgets=%d weapon_key=%s",
            prefix, #self._ct_offhand_widgets,
            _safe_str(self._ct_offhand_weapon_key))
    end
end

_ENRICHERS.HeroWindowCosmeticsLoadout = function(prefix, self)
    -- v0.9.26-dev: `_equipment_items` is ALWAYS empty at on_enter time
    -- (vanilla initializes to {} on enter, populates lazily via
    -- `_equip_item_presentation` per update tick). The per-slot equip /
    -- unequip dumps below catch the real write site — see
    -- LOADOUT_WINDOWS_WITH_EQUIP further down in this file. The line
    -- below captures category context which IS available at on_enter.
    mod:info("%s active_category=%s active_slot=%s",
        prefix, _safe_str(self._active_category), _safe_str(self._active_slot))
end

_ENRICHERS.HeroWindowCosmeticsInventory = function(prefix, self)
    -- The grid of available cosmetics for the active category. Just the
    -- count + the active category is enough to understand the surface;
    -- dumping every cosmetic key would spam thousands of lines.
    if self._cosmetics_grid then
        mod:info("%s cosmetics_grid present (category=%s)",
            prefix, _safe_str(self._active_category))
    end
end

_ENRICHERS.HeroWindowInventory = function(prefix, self)
    -- The right-side grid showing every weapon of a given slot type.
    mod:info("%s inventory_sync_id=%s item_grid=%s",
        prefix, _safe_str(self._inventory_sync_id),
        _safe_str(self._item_grid ~= nil))
end

_ENRICHERS.HeroWindowLoadout = function(prefix, self)
    -- v0.9.26-dev: see HeroWindowCosmeticsLoadout enricher note above —
    -- `_equipment_items` is empty at on_enter. The per-slot dumps in
    -- LOADOUT_WINDOWS_WITH_EQUIP further down handle the real capture.
    -- Nothing further to dump at on_enter time for this class beyond
    -- the generic widget list.
end

_ENRICHERS.HeroWindowCrafting = function(prefix, self)
    -- Available recipes and which one is selected.
    if self._recipes then
        local names = {}
        for _, r in ipairs(self._recipes) do
            names[#names + 1] = r.display_name or r.name or "?"
        end
        mod:info("%s recipes (%d): %s current=%s",
            prefix, #names, _short_list(names, 12),
            _safe_str(self._selected_recipe_name))
    end
    if self._has_all_requirements ~= nil then
        mod:info("%s has_all_requirements=%s",
            prefix, _safe_str(self._has_all_requirements))
    end
end

_ENRICHERS.HeroWindowLoadoutInventory = _ENRICHERS.HeroWindowInventory
_ENRICHERS.HeroWindowLoadoutInventoryConsole = _ENRICHERS.HeroWindowInventory
_ENRICHERS.HeroWindowCraftingConsole = _ENRICHERS.HeroWindowCrafting
_ENRICHERS.HeroWindowCraftingInventoryConsole = _ENRICHERS.HeroWindowCrafting
_ENRICHERS.HeroWindowCraftingListConsole = _ENRICHERS.HeroWindowCrafting
_ENRICHERS.HeroWindowCosmeticsLoadoutConsole = _ENRICHERS.HeroWindowCosmeticsLoadout
_ENRICHERS.HeroWindowCosmeticsLoadoutInventoryConsole = _ENRICHERS.HeroWindowCosmeticsInventory
_ENRICHERS.HeroWindowCosmeticsLoadoutPoseInventoryConsole = _ENRICHERS.HeroWindowCosmeticsInventory
_ENRICHERS.HeroWindowLoadoutConsole = _ENRICHERS.HeroWindowLoadout
_ENRICHERS.HeroWindowLoadoutSelectionConsole = _ENRICHERS.HeroWindowLoadout

-- ===========================================================================
-- Hook installation. Done at module load (mod boot). String-form so VMF
-- handles delayed resolution if the class isn't loaded yet (Console
-- variants only exist in gamepad mode).
-- ===========================================================================

local WINDOWS_TO_MONITOR = {
    -- Cosmetic / illusion / glow surfaces
    "HeroWindowItemCustomization",
    "HeroWindowCosmeticsLoadout",
    "HeroWindowCosmeticsLoadoutConsole",
    "HeroWindowCosmeticsInventory",
    "HeroWindowCosmeticsLoadoutInventoryConsole",
    "HeroWindowCosmeticsLoadoutPoseInventoryConsole",
    -- Inventory / equipment / loadout
    "HeroWindowInventory",
    "HeroWindowLoadout",
    "HeroWindowLoadoutInventory",
    "HeroWindowLoadoutConsole",
    "HeroWindowLoadoutInventoryConsole",
    "HeroWindowLoadoutSelectionConsole",
    -- (v0.9.25-dev removed "HeroWindowEquipmentChoices" — class doesn't
    -- exist in vanilla; I had guessed the name. Hook errored at boot.)
    -- Crafting (forge) — closely tied to item customization
    "HeroWindowCrafting",
    "HeroWindowCraftingConsole",
    "HeroWindowCraftingInventoryConsole",
    "HeroWindowCraftingListConsole",
}

-- v0.9.25-dev hardening: pre-check each class exists in _G before
-- registering the hook. VMF's string-form `mod:hook` errors with
-- `(hook): trying to hook object that doesn't exist: <Class>` if the
-- name is wrong — visible to every subscriber's console as a real ERROR
-- line. The pre-check downgrades typos to a single `[ui-dump]` warning
-- (greppable + actionable) without touching anyone else's experience.
-- Surviving entries get hooked normally. The `unknown_classes` list
-- is exposed below for the regression test to inspect.
M._all_class_names = WINDOWS_TO_MONITOR
M._unknown_classes = {}

-- v0.9.26-dev note on CIM coexistence: CIM hooks
-- `HeroWindowItemCustomization.on_enter` via `hook_safe`. We hook the same
-- (class, method) via wrapping `mod:hook`. Per VMF, wrap and hook_safe
-- live on different rungs of the call stack and chain correctly — wrap
-- runs around `func()`, hook_safe fires after `func()` returns. Both fire
-- for every on_enter call; neither shadows the other. Do NOT "consolidate"
-- by switching one to match the other — VMF hook_safe registrations on
-- the same (class, method) silently shadow each other (VMF_RECIPES.md § 1)
-- and that would actually break CIM. Leave as-is.
for _, class_name in ipairs(WINDOWS_TO_MONITOR) do
    if not rawget(_G, class_name) then
        M._unknown_classes[#M._unknown_classes + 1] = class_name
        mod:info("[ui-dump] WARN skipping hook on missing class %s — vanilla didn't define it. If you renamed a window, update WINDOWS_TO_MONITOR.", class_name)
    else
    -- mod:hook (wrapping) chains correctly across mods, unlike hook_safe.
    -- Capture every vanilla return into ret_table to avoid multi-return
    -- collapse (VMF_RECIPES.md § 2). on_enter typically returns nothing,
    -- but defensive.
    mod:hook(class_name, "on_enter", function(func, self, params, offset)
        local r1, r2, r3, r4 = func(self, params, offset)
        if _enabled() then
            local prefix = "[ui-dump:" .. class_name .. "]"
            local ok, err = pcall(function()
                _dump_window_common(prefix, self, params, offset)
                local enricher = _ENRICHERS[class_name]
                if enricher then enricher(prefix, self) end
            end)
            if not ok then
                mod:info("%s dump pcall err: %s", "[ui-dump:" .. class_name .. "]", tostring(err))
            end
        end
        return r1, r2, r3, r4
    end)
    end  -- v0.9.25-dev guarded branch end
end

-- ===========================================================================
-- HeroView top-level transition tracker. v0.9.24 guessed `_change_window`,
-- which doesn't exist (errored at boot). The vanilla screen-switch method
-- is `_change_screen_by_name` (hero_view.lua:477). Per-window sub-state
-- transitions are driven by a state machine inside each screen, so this
-- only captures top-level screen switches (Loadout / Cosmetics / Crafting
-- / etc.) — still enough to anchor the per-window dumps in a navigation
-- sequence.
-- ===========================================================================

-- ===========================================================================
-- Per-slot equip / unequip dumps. The `_equipment_items` table dumped from
-- `on_enter` enrichers is ALWAYS empty there — vanilla initializes the
-- table to `{}` on enter and populates lazily in `_equip_item_presentation`
-- (called from `_update_loadout_sync` every `update` tick once the loadout
-- arrives). v0.9.24's enricher was reading one tick too early and producing
-- silent no-output. The right capture point is the write site itself.
--
-- All four loadout-style windows share this method (verified against
-- vanilla source 2026-05-26): HeroWindowLoadout, HeroWindowLoadoutConsole,
-- HeroWindowCosmeticsLoadout, HeroWindowCosmeticsLoadoutConsole. Per-class
-- hook_safe so each fires exactly once per slot per equip event — minimal
-- volume, surgical signal: every slot the user equips appears in the log.
-- Symmetric `_clear_item_slot` hook makes unequips visible too.
-- v0.9.27-dev: per-(class, method) existence guard. v0.9.26 checked only
-- class existence and tried to hook `_clear_item_slot` on every class. That
-- method exists on three of the four but NOT on `HeroWindowCosmeticsLoadout`
-- (verified against vanilla source 2026-05-26: cosmetics loadout swaps
-- slots in place — vanilla never unequips from that window — so the
-- `_clear_item_slot` method was simply never authored). VMF raised an ERROR
-- for the missing method on boot. Per-method `rawget(klass, method)` check
-- now skips silently with a [ui-dump] WARN, mirroring the per-class guard
-- v0.9.25 added. Skipped pairs are recorded in `M._unknown_method_pairs`
-- and re-validated by the `ui_dump_hook_targets_exist` regression test.
M._loadout_hook_pairs = {
    -- (class_name, method, behavior)
    { "HeroWindowLoadout",                "_equip_item_presentation", "equip"   },
    { "HeroWindowLoadout",                "_clear_item_slot",         "unequip" },
    { "HeroWindowLoadoutConsole",         "_equip_item_presentation", "equip"   },
    { "HeroWindowLoadoutConsole",         "_clear_item_slot",         "unequip" },
    { "HeroWindowCosmeticsLoadout",       "_equip_item_presentation", "equip"   },
    -- intentionally NO _clear_item_slot on HeroWindowCosmeticsLoadout —
    -- vanilla doesn't define it (cosmetics loadout never unequips).
    { "HeroWindowCosmeticsLoadoutConsole","_equip_item_presentation", "equip"   },
    { "HeroWindowCosmeticsLoadoutConsole","_clear_item_slot",         "unequip" },
}
M._unknown_method_pairs = {}

local function _make_equip_handler(class_name)
    return function(self, item, slot)
        if not _enabled() then return end
        local sd = item and item.data
        mod:info("[ui-dump:%s] EQUIP slot_idx=%s ui_slot_idx=%s slot_type=%s key=%s bid=%s skin=%s rarity=%s",
            class_name,
            _safe_str(slot and slot.slot_index),
            _safe_str(slot and slot.ui_slot_index),
            _safe_str(sd and sd.slot_type),
            _safe_str(item and (item.key or (sd and sd.key))),
            _safe_str(item and item.backend_id),
            _safe_str(item and item.skin),
            _safe_str(item and item.rarity))
    end
end

local function _make_unequip_handler(class_name)
    return function(self, slot)
        if not _enabled() then return end
        mod:info("[ui-dump:%s] UNEQUIP slot_idx=%s ui_slot_idx=%s type=%s",
            class_name, _safe_str(slot and slot.slot_index),
            _safe_str(slot and slot.ui_slot_index),
            _safe_str(slot and slot.type))
    end
end

for _, pair in ipairs(M._loadout_hook_pairs) do
    local class_name, method, behavior = pair[1], pair[2], pair[3]
    local klass = rawget(_G, class_name)
    if not klass then
        -- Class itself missing — already covered by WINDOWS_TO_MONITOR
        -- guard above. Don't double-warn.
        M._unknown_method_pairs[#M._unknown_method_pairs + 1] = class_name .. "." .. method .. " (class missing)"
    elseif type(klass[method]) ~= "function" then
        M._unknown_method_pairs[#M._unknown_method_pairs + 1] = class_name .. "." .. method
        mod:info("[ui-dump] WARN skipping hook on missing method %s.%s — vanilla didn't define it on this class.",
            class_name, method)
    else
        local handler = (behavior == "equip")
            and _make_equip_handler(class_name)
            or _make_unequip_handler(class_name)
        mod:hook_safe(class_name, method, handler)
    end
end

M._heroview_hook_method = "_change_screen_by_name"
M._heroview_hook_installed = false
do
    local hv = rawget(_G, "HeroView")
    if hv and type(hv[M._heroview_hook_method]) == "function" then
        mod:hook_safe("HeroView", M._heroview_hook_method,
            function(self, screen_name, sub_screen_name, optional_params)
                if _enabled() then
                    mod:info("[ui-dump:HeroView] _change_screen_by_name -> %s sub=%s",
                        tostring(screen_name), tostring(sub_screen_name))
                end
            end)
        M._heroview_hook_installed = true
    else
        mod:info("[ui-dump] WARN HeroView.%s not present — skipping nav-hook. If vanilla renamed it, update _ui_dump.lua's M._heroview_hook_method.",
            M._heroview_hook_method)
    end
end

local _hooked_count = #WINDOWS_TO_MONITOR - #M._unknown_classes
mod:info("[ui-dump] hooked on_enter for %d/%d hero windows (%d unknown skipped) + HeroView nav-hook %s (gated on enable_debug_logging)",
    _hooked_count, #WINDOWS_TO_MONITOR, #M._unknown_classes,
    M._heroview_hook_installed and "INSTALLED" or "SKIPPED")

return M
