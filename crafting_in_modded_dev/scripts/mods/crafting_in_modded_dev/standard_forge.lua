--[[
standard_forge — Hooks the Keep's standard crafting menus to work in modded realm
without consuming crafting materials.

In modded realm the player has zero crafting_material items in their PlayFab
inventory, so every CraftPage's `setup_recipe_requirements` reports
`_has_all_requirements = false` and disables the craft button. PlayFab also rejects
any actual `craft()` request because the server-side ingredient check fails.

Strategy (same pattern as the Athanor):
  1. UI layer — post-hook `setup_recipe_requirements` on each material-gated CraftPage
     to force `_has_all_requirements = true` and re-enable the button.
  2. Backend layer — when `HeroWindowCrafting` is open, set `_standard_forge_active`
     and **block all PlayFab commits**. Without that, mutating an existing inventory
     item triggers a "Backend rejected the challenge response -1" anti-tamper kick
     (this is what crashed v0.2.0). Hook `BackendInterfaceCraftingPlayfab._get_valid_recipe`
     to bypass material validation, and `craft()` to short-circuit the PlayFab queue
     and synthesize results locally via per-recipe `synth.<recipe_name>` functions.

Mutations are session-only. On game restart PlayFab reloads the canonical inventory
and reverts everything. This matches how the Athanor handles property/trait edits.
]]

local mod = get_mod("cim_dev")
local template_selector = mod:dofile("scripts/mods/crafting_in_modded_dev/_cim_template_selector")
mod._cim_template_selector = template_selector

-- ============================================================
-- Lifecycle: track when the standard forge UI is open
-- ============================================================
-- Stored on the shared `mod` object so the single commit hook in
-- crafting_in_modded.lua can check this flag without us rehooking commit
-- (rehook would warn + drop the second registration → commits leak to
-- PlayFab → "Backend rejected the challenge response -1" kick).

mod._cim_standard_forge_active = false

local function _is_active() return mod._cim_standard_forge_active end

-- Forward-declared so the jewelry-pin block inside the
-- `_MATERIAL_GATED_PAGES` hook body (below, around line 240) can reference
-- `synth[pinned_recipe]` before the canonical `local synth = {}` further down
-- the file (~line 430). Without this forward declaration the closure binds
-- to global `synth` (nil), the `if pinned_recipe and synth[pinned_recipe]`
-- gate always evaluates false, and jewelry templates fall through to vanilla's
-- random-slot `craft_jewellery` recipe — silently breaking the v0.7.27 marquee
-- feature. Hardening added in v0.7.28-alpha alongside the rehook-warning fix.
-- See `feedback_lua_forward_reference`.
local synth

-- Forward-declared so `_make_craft_synth` (further down) can reference it
-- before the canonical assignment near the template-cache block. Without this
-- forward declaration the closure binds to a nil global, the slot_type
-- sanity-gate added in v0.7.15 silently no-ops, and crafting_material_scrap-
-- style items would slip past again. See `feedback_lua_forward_reference`.
local _CRAFTABLE_SLOT_TYPES = { melee = true, ranged = true, ring = true, necklace = true, trinket = true }

-- DLC ownership gate. Vanilla weapons gated behind unowned DLC stay locked
-- even in modded realm — modded crafting is a power-up over the vanilla
-- progression unlocks (career levels, crafting materials), NOT a bypass for
-- paid DLC content. Same `Managers.unlock:is_dlc_unlocked` check the game
-- uses elsewhere, and same pattern illusion_swap.lua uses for skins.
local function _item_requires_unowned_dlc(item_key)
    if not item_key or not ItemMasterList then return false end
    local data = rawget(ItemMasterList, item_key)
    if not data or not data.required_dlc then return false end
    if not Managers.unlock then return false end
    return not Managers.unlock:is_dlc_unlocked(data.required_dlc)
end

mod._cim_item_requires_unowned_dlc = _item_requires_unowned_dlc

-- Versus-shadow gate (2026-06-18). cim INTENTIONALLY surfaces vs_* Versus
-- carousel weapons as craftable (it clears their mechanisms on craft so the
-- result shows in the Adventure grid -- Gallant's Blade, Soldier's Coach Gun,
-- etc.; see _ensure_item_adventure_visible + memory
-- reference_vt2_versus_items_hidden_in_adventure). So we must NOT blanket-exclude
-- versus items. BUT a vs_* item that shares its display_name with a REAL
-- (non-versus) Adventure weapon -- e.g. vs_wh_hammer_book vs the real
-- wh_hammer_book -- is a pure duplicate: cim's craft list dedups by display_name,
-- so the versus twin can win the dedup and render as a LOCKED, uncraftable row
-- (backend_id = nil) that HIDES the real craftable weapon. Drop a versus item
-- ONLY when such a real twin exists; unique vs_* weapons (no real twin) are
-- untouched and stay craftable. Build the real-display_name set ONCE per
-- list-build and pass it in so the per-item check stays O(1) (overall O(n), not
-- O(n^2)).
local function _cim_is_versus(data)
    local m = type(data) == "table" and data.mechanisms
    return m ~= nil and table.contains(m, "versus")
end

local function _cim_real_display_names()
    local set = {}
    for _, d in pairs(ItemMasterList) do
        if type(d) == "table" and d.display_name and not _cim_is_versus(d) then
            set[d.display_name] = true
        end
    end
    return set
end

local function _cim_versus_shadowed(data, real_names)
    return _cim_is_versus(data) and data.display_name ~= nil
        and real_names ~= nil and real_names[data.display_name] == true
end

mod._cim_is_versus = _cim_is_versus
mod._cim_real_display_names = _cim_real_display_names
mod._cim_versus_shadowed = _cim_versus_shadowed

-- Both the desktop ("HeroWindowCrafting") and inventory-tab/gamepad
-- ("HeroWindowCraftingConsole") variants need lifecycle hooks. The user's
-- Crashify trace showed `Enter Substate HeroWindowCraftingConsole` on PC —
-- the inventory crafting tab uses the Console class regardless of input
-- device, so missing this variant let the craft request through to PlayFab
-- → EAC challenge → kick (BACKEND_PLAYFAB_ERRORS.ERR_PLAYFAB_EAC_ERROR / 511).
-- ONE hook_safe per Class+method. VMF silently shadows duplicate hook_safe
-- registrations (memory: feedback_vmf_hook_safe_no_chain), so the cache rebuild
-- has to live inside this same callback rather than a sibling hook block. The
-- function is resolved at call time via `mod._cim_rebuild_template_cache`, so
-- it's safe to invoke before the assignment further down the file runs.
-- ============================================================
-- Customization menu (gear-icon → reroll properties / reroll traits)
-- ============================================================
-- The gear-icon menu is `HeroWindowItemCustomization`. Its craft button
-- is gated by three conditions (`hero_window_item_customization.lua:1928`):
--   disable_button = force_disable or not has_all_requirements or script_data["eac-untrusted"]
-- In modded realm `script_data["eac-untrusted"] = true` → button always
-- greyed → user can't reroll props or traits via the cosmetics menu.
--
-- Two fixes:
--   1. Lifecycle hooks below also flip `_cim_standard_forge_active` so
--      cim's `craft()` hook intercepts the click (otherwise vanilla
--      tries to send a PlayFab request that the modded backend rejects
--      with the EAC-untrusted kick).
--   2. Wrapping hook on `_update_state_craft_button` does two jobs:
--      (a) For `apply_weapon_skin`: temporarily clears `eac-untrusted`
--          around the original call so vanilla's state check doesn't
--          bake in the modded gate (migrated from illusion_swap.lua to
--          prevent a duplicate `mod:hook*` on the same class+method —
--          VMF silently drops the second registration with a
--          "Attempting to rehook active hook" warning).
--      (b) When the standard forge UI is active: overrides the
--          disable_button write AFTER vanilla sets it, dropping the
--          eac-untrusted term but keeping force_disable + requirements.
mod:hook("HeroWindowItemCustomization", "_update_state_craft_button", function(func, self, recipe_name, ...)
    local result
    if script_data["eac-untrusted"] and recipe_name == "apply_weapon_skin" then
        local saved = script_data["eac-untrusted"]
        script_data["eac-untrusted"] = false
        result = func(self, recipe_name, ...)
        script_data["eac-untrusted"] = saved
    else
        result = func(self, recipe_name, ...)
    end

    -- Post-write override: re-enable button for the standard forge UI
    -- (gear-icon reroll-props / reroll-traits / upgrade / apply-skin tabs).
    if mod._cim_standard_forge_active then
        local btn = self._widgets_by_name and self._widgets_by_name.craft_button
        if btn then
            local has_all = self._has_all_crafting_requirements
            if has_all == nil then has_all = true end
            local force_disable = select(3, ...)  -- (button_text, glow_color, force_disable, offset)
            btn.content.button_hotspot.disable_button = force_disable or not has_all or false
        end
    end

    return result
end)

-- ============================================================
-- One-shot trim: existing items in the mirror with >2 properties
-- ============================================================
-- Consolidated into the canonical `BackendManagerPlayFab._create_interfaces`
-- hook_safe in crafting_in_modded.lua (the `_forge_load` callback). A second
-- registration here was silently dropped by VMF as a duplicate, leaving the
-- trim logic dead. See memory `feedback_vmf_hook_safe_no_chain`. Fixed in
-- v0.7.28-alpha.

-- ============================================================
-- Defensive guard against >2-property items (crash fix v0.7.25)
-- ============================================================
-- Crash report 2026-05-22: `hero_window_item_customization.lua:1213` —
-- `content[option_hotspot_name].disable_button = false` faulted on
-- `button_hotspot_3` (nil). The `item_properties` widget only ships hotspots
-- 1 and 2 because vanilla caps weapon/jewelry properties at 2. When cim's
-- Athanor pile-up writes 3+ properties to an accessory (`_forge_apply_to_*`
-- allows it via the 10-bubble layer), the iteration at vanilla line 1201-1215
-- runs N times for N stored properties → indexes a missing widget on N>=3.
-- Replace the function with a bounded version that skips writes for missing
-- widgets. Cosmetic-only — the extra properties are still applied to the buff
-- system, just not surfaced in the Customization → Apply Skin tab's preview.
mod:hook("HeroWindowItemCustomization", "_update_property_option", function(func, self)
    local item = self:_get_item(self._item_backend_id)
    if not item or not item.properties then return end
    local properties_widget = self._widgets_by_name and self._widgets_by_name.item_properties
    if not properties_widget then return end
    local content = properties_widget.content
    if not content then return end
    local property_count = 0
    for property_key, property_value in pairs(item.properties) do
        property_count = property_count + 1
        local hotspot_name = "button_hotspot_" .. property_count
        local text_name = "option_text_" .. property_count
        local hotspot = content[hotspot_name]
        if hotspot then
            local property_data = WeaponProperties and WeaponProperties.properties
                                  and WeaponProperties.properties[property_key]
            if property_data then
                local ok, title_text = pcall(UIUtils.get_property_description,
                                             property_key, property_value)
                hotspot.disable_button = false
                if ok and title_text then content[text_name] = title_text end
            end
        end
        -- Silently drop the write when the widget slot doesn't exist (item
        -- has more properties than vanilla's Customization UI was authored
        -- for). Prevents the nil-index crash; the property is still in
        -- item.properties and still applies to the buff system.
    end
end)

for _, klass in ipairs({ "HeroWindowItemCustomization", "HeroWindowCrafting", "HeroWindowCraftingConsole" }) do
    local class_for_dump = klass
    mod:hook_safe(klass, "on_enter", function(self)
        mod._cim_standard_forge_active = true
        if mod._cim_rebuild_template_cache then
            mod._cim_rebuild_template_cache()
        end
        -- Debug autodump (no-op unless debug_mode setting is ON). Single
        -- consolidated callback per (class, method) — VMF silently drops a
        -- sibling hook_safe registration. See feedback_vmf_hook_safe_no_chain.
        if mod._cim_autodump_forge_open then
            pcall(mod._cim_autodump_forge_open, class_for_dump, self)
        end
    end)
    mod:hook_safe(klass, "on_exit", function(self)
        mod._cim_standard_forge_active = false
    end)
end

-- ============================================================
-- UI layer: force-enable craft buttons for material-gated recipes
-- ============================================================

local _MATERIAL_GATED_PAGES = {
    "CraftPageCraftItem",         "CraftPageCraftItemConsole",
    "CraftPageRollProperties",    "CraftPageRollPropertiesConsole",
    "CraftPageRollTrait",         "CraftPageRollTraitConsole",
    "CraftPageUpgradeItem",       "CraftPageUpgradeItemConsole",
    "CraftPageApplySkin",         "CraftPageApplySkinConsole",
    "CraftPageConvertDust",       "CraftPageConvertDustConsole",
}

-- ============================================================
-- Jewelry slot pinning + per-slot button label (feedback #6)
-- ============================================================
-- Vanilla `CraftPageCraftItem.setup_recipe_requirements`
-- (craft_page_craft_item.lua:62-78, Console at :69-85) hard-pins
-- `self._recipe_name = "craft_jewellery"` whenever a jewelry template is
-- dropped, regardless of slot. The synth then picks a random jewelry slot —
-- so dropping a charm template might craft a necklace. User wants three
-- explicit options.
--
-- vanilla's UI does NOT support adding new pages to `page_settings` (local-
-- to-module at hero_window_crafting.lua:18). What we CAN do: post-hook this
-- function and substitute one of cim's per-slot synth recipes
-- (`craft_necklace` / `craft_charm` / `craft_trinket`) based on the dropped
-- item's actual slot_type. The synth then crafts exactly that slot.
--
-- Combined with the dynamic button label (`craft_button` / page title), the
-- effective UX is: drop a necklace template → "CRAFT NECKLACE" → necklace
-- crafted; drop a charm template → "CRAFT CHARM" → charm crafted; drop a
-- trinket template → "CRAFT TRINKET" → trinket crafted. Three "buttons" via
-- three deterministic recipes.
--
-- Lives inside the `_MATERIAL_GATED_PAGES` hook body below (gated on the
-- two CraftPageCraftItem klasses) — a sibling `mod:hook_safe` on the same
-- two class+method pairs was silently dropped by VMF per memory
-- `feedback_vmf_hook_safe_no_chain`. Consolidated in v0.7.28-alpha.
local _JEWELRY_SLOT_TO_RECIPE = {
    necklace = "craft_necklace",
    ring     = "craft_charm",
    trinket  = "craft_trinket",
}
local _JEWELRY_SLOT_TO_LABEL = {
    necklace = "CRAFT NECKLACE",
    ring     = "CRAFT CHARM",
    trinket  = "CRAFT TRINKET",
}
local _WEAPON_SLOTS_TO_LABEL = {
    melee  = "CRAFT WEAPON",
    ranged = "CRAFT WEAPON",
}

for _, klass in ipairs(_MATERIAL_GATED_PAGES) do
    mod:hook_safe(klass, "setup_recipe_requirements", function(self)
        self._has_all_requirements = true
        if self._set_craft_button_disabled then
            self:_set_craft_button_disabled(false)
        end
        -- Hide the per-recipe material requirement display ("X/Y scrap, etc").
        -- Modded crafting doesn't consume materials, so showing the cost is
        -- misleading. Sweep up to 16 material_text widgets just to be safe.
        local widgets_by_name = self._widgets_by_name
        if widgets_by_name then
            for i = 1, 16 do
                local w = widgets_by_name["material_text_" .. i]
                if w and w.content then w.content.visible = false end
                local icon = widgets_by_name["material_icon_" .. i]
                if icon and icon.content then icon.content.visible = false end
            end
        end

        -- Jewelry slot pinning + per-slot button label.
        -- Only the two CraftPageCraftItem variants participate (the other
        -- material-gated pages — RollProperties / RollTrait / etc. — don't
        -- pick a new slot, so the jewelry logic is a no-op there). Consolidated
        -- from a sibling hook_safe registration that VMF silently dropped.
        if klass == "CraftPageCraftItem" or klass == "CraftPageCraftItemConsole" then
            if not _is_active() then return end
            local added_bid = self._craft_items and self._craft_items[1]
            if not added_bid then return end
            local item_iface = Managers.backend and Managers.backend:get_interface("items")
            local item_data = item_iface and item_iface:get_item_masterlist_data(added_bid)
            local slot = item_data and item_data.slot_type
            if not slot then return end

            -- Pin recipe_name to the slot-specific synth (jewelry only — weapon
            -- is already a single slot at the synth level).
            local pinned_recipe = _JEWELRY_SLOT_TO_RECIPE[slot]
            if pinned_recipe and synth[pinned_recipe] then
                self._recipe_name = pinned_recipe
            end

            -- Relabel the page title + craft button so the user sees what
            -- they're actually crafting. Vanilla title widget is `title_text`
            -- on the parent HeroWindowCrafting (line 341 of that file writes
            -- `Localize(recipe.display_name)`). We can't reach the parent from
            -- the page directly without snooping, so set the craft button text
            -- (`craft_button.content.title_text`) which is what the user clicks.
            local label = _JEWELRY_SLOT_TO_LABEL[slot] or _WEAPON_SLOTS_TO_LABEL[slot]
            local btn = widgets_by_name and widgets_by_name.craft_button
            if btn and btn.content and label then
                btn.content.title_text = label
                if btn.content.button_text then btn.content.button_text = label end
            end
            -- Also try the parent window's title for visibility above the page.
            local parent = self.parent or self.super_parent
            local parent_widgets = parent and parent._widgets_by_name
            local title = parent_widgets and parent_widgets.title_text
            if title and title.content and label then
                title.content.text = label
            end
        end
    end)
end

-- ============================================================
-- Craft-completion feedback for the Console / old-UI craft pages
-- ============================================================
-- Feedback #4: when crafting via the legacy / gamepad UI, vanilla's
-- `_play_sound("play_gui_craft_forge_button_completed")` only fires on a
-- successful craft path that returned truthy. In modded realm cim short-
-- circuits the PlayFab path (silent_drop returns a no-op id), so the
-- "complete" sound never plays and the user gets no audible confirmation.
-- The salvage page is the most-visible offender. Hook `_update_craft_items`
-- on the Console variants and emit the sound when a craft just finished
-- (`_presenting_rewards` flag flips true).
local _FEEDBACK_PAGES = {
    "CraftPageSalvageConsole",
    "CraftPageCraftItemConsole",
    "CraftPageRollPropertiesConsole",
    "CraftPageRollTraitConsole",
    "CraftPageUpgradeItemConsole",
    "CraftPageApplySkinConsole",
}
for _, klass in ipairs(_FEEDBACK_PAGES) do
    if rawget(_G, klass) then
        mod:hook_safe(klass, "_update_craft_items", function(self)
            if self._presenting_rewards and not self._cim_played_complete then
                self._cim_played_complete = true
                if self._play_sound then
                    pcall(self._play_sound, self, "play_gui_craft_forge_button_completed")
                end
            elseif not self._presenting_rewards then
                self._cim_played_complete = false
            end
        end)
    end
end

-- Hide the inventory window's top crafting-material panel (the row of
-- "Scrap: 0  Blue Dust: 0  Orange Dust: 0..." stats). Modded play has no
-- materials, so the row is just clutter. Post-hook so vanilla writes its
-- values first, then we wipe visibility on every refresh.
local function _hide_material_panel(self)
    local widgets_by_name = self._widgets_by_name
    if not widgets_by_name then return end
    for i = 1, 16 do
        local w = widgets_by_name["material_text_" .. i]
        if w and w.content then w.content.visible = false end
    end
end

-- Only the Console variant exists in current VT2 builds. Earlier versions of
-- this mod also tried to hook a non-Console `HeroWindowCraftingInventory` —
-- VMF logged "trying to hook object that doesn't exist" because that class
-- isn't defined at runtime. Guard with `rawget` so we don't churn the log if
-- it returns or stays missing.
mod:hook_safe("HeroWindowCraftingInventoryConsole", "_update_crafting_material_panel", _hide_material_panel)
if rawget(_G, "HeroWindowCraftingInventory") then
    mod:hook_safe("HeroWindowCraftingInventory", "_update_crafting_material_panel", _hide_material_panel)
end

-- ============================================================
-- Backend layer: skip material validation
-- ============================================================

-- cim-only synth names not in vanilla `crafting_recipes_by_name`. v0.7.27+
-- adds `craft_necklace` / `craft_charm` / `craft_trinket` so the jewelry-
-- slot-pin hook in `setup_recipe_requirements` can route to slot-specific
-- synths. Vanilla's `_crafting_recipes_by_name` doesn't know these, so the
-- lookup at the start of `_get_valid_recipe` returns nil. Catch those names
-- here and synthesize a minimal recipe shim — the craft() dispatcher only
-- reads `recipe.name` to look up `synth[recipe.name]`, so we don't need a
-- full recipe table.
local _CIM_ONLY_RECIPE_NAMES = {
    craft_necklace = true,
    craft_charm    = true,
    craft_trinket  = true,
}

mod:hook("BackendInterfaceCraftingPlayfab", "_get_valid_recipe", function(func, self, item_backend_ids, recipe_override)
    if not _is_active() or not recipe_override then
        return func(self, item_backend_ids, recipe_override)
    end
    local recipe = self._crafting_recipes_by_name[recipe_override]
    if not recipe and _CIM_ONLY_RECIPE_NAMES[recipe_override] then
        recipe = { name = recipe_override }
    end
    if not recipe then
        return func(self, item_backend_ids, recipe_override)
    end
    local valid_ids = {}
    for i, bid in ipairs(item_backend_ids) do
        valid_ids[i] = { amount = 1, backend_id = bid }
    end
    return recipe, valid_ids
end)

-- ============================================================
-- Per-recipe local synthesis
-- ============================================================

local _RARITY_CHAIN = { "plentiful", "common", "rare", "exotic", "unique" }
local _RARITY_INDEX = {}
for i, r in ipairs(_RARITY_CHAIN) do _RARITY_INDEX[r] = i end

-- Read the base_power_level slider (data widget at crafting_in_modded_data.lua).
-- Falls back to 300 if VMF isn't ready yet or the setting hasn't been migrated.
local function _cim_base_power()
    local v = mod:get("base_power_level")
    if type(v) ~= "number" then return 300 end
    -- Slider is 0-950 step 50; clamp belt-and-suspenders in case a stale config
    -- ever held an out-of-range value.
    if v < 0 then return 0 end
    if v > 950 then return 950 end
    return v
end
mod._cim_base_power = _cim_base_power

-- Per-property stored-value mapping for prefilled crafts. Vanilla's buff
-- system reads `params.variable_value` from `item.properties[key]`, then
-- buff_extension.lua:200-237 resolves the final buff multiplier. For most
-- properties storing 1.0 produces max-tier (lerp at value=1.0 hits the
-- variable_multiplier_table's upper bound). For movespeed in DEFAULT mode the
-- vanilla buff template has a static `multiplier = 1.05` — value 1.0 just
-- gates application, the multiplier is fixed. For movespeed in 2PCT mode we
-- patch the buff template to `variable_multiplier = { 1.0, 1.10 }` so the
-- lerp DOES scale — and prefill at value 1.0 then lands at +10% (max).
-- Either way, storing 1.0 produces the correct max-tier effect.
local function _safe_property_value(prop_key)
    return 1.0
end

-- Bind the forward-declared `synth` upvalue (see top of file). Was
-- `local synth = {}` until v0.7.28-alpha; the redeclaration shadowed the
-- forward-decl and broke the jewelry-pin closure further up.
synth = {}

local function _result_for_modified(backend_id)
    return { { backend_id, [3] = 1 } }
end

-- ---- salvage: destroy each input item ----
-- The result table must contain PRODUCED MATERIALS (vanilla salvage returns
-- scrap / dust bids), NOT the consumed weapon bids. The salvage page's
-- `on_craft_completed` iterates the result and calls `_set_reward_material_by_index`
-- which internally does `item_interface:get_key(backend_id)` → unguarded
-- `item.key` access; passing a just-removed weapon bid crashes the game.
-- We don't produce any materials in modded, so the result is empty.
--
-- For vanilla items: removal is session-only (PlayFab restores them on restart
-- because the commit-block prevented us from telling the server). For modded
-- items registered via `_cim_register_craft`: also unregister from the save
-- layer so they don't get re-injected next launch, and clear any modded-loadout
-- entry that points to the salvaged backend_id.
synth.salvage = function(self, item_backend_ids)
    local mirror = self._backend_mirror
    local unregistered = 0
    for i, bid in ipairs(item_backend_ids) do
        mirror:remove_item(bid)
        if mod._cim_unregister_craft then
            mod._cim_unregister_craft(bid)
            unregistered = unregistered + 1
        end
        if mod._cim_clear_modded_loadout_for_bid then
            mod._cim_clear_modded_loadout_for_bid(bid)
        end
    end
    mod:echo("[cim] Salvaged " .. tostring(#item_backend_ids) .. " item(s)" ..
             (unregistered > 0 and (" (" .. unregistered .. " modded crafts unregistered)") or ""))
    return {}
end

-- ---- apply_weapon_skin: weapon = item[1], skin = item[2]; set weapon.skin ----
synth.apply_weapon_skin = function(self, item_backend_ids)
    local mirror = self._backend_mirror
    local item_interface = Managers.backend:get_interface("items")
    local weapon_bid = item_backend_ids[1]
    local skin_bid = item_backend_ids[2]
    if not weapon_bid or not skin_bid then return {} end
    local skin_data = item_interface:get_item_masterlist_data(skin_bid)
    local skin_key = skin_data and skin_data.key
    if not skin_key then return {} end

    local item = item_interface:get_item_from_id(weapon_bid)
    if item then
        item.skin = skin_key
        if item.CustomData then item.CustomData.skin = skin_key end
        mirror:update_item(weapon_bid, item)
    end
    return _result_for_modified(weapon_bid)
end

-- ---- extract_weapon_skin: clear weapon.skin ----
synth.extract_weapon_skin = function(self, item_backend_ids)
    local mirror = self._backend_mirror
    local item_interface = Managers.backend:get_interface("items")
    local weapon_bid = item_backend_ids[1]
    if not weapon_bid then return {} end

    local item = item_interface:get_item_from_id(weapon_bid)
    if item then
        item.skin = nil
        if item.CustomData then item.CustomData.skin = nil end
        mirror:update_item(weapon_bid, item)
    end
    return _result_for_modified(weapon_bid)
end

-- ---- upgrade_item_rarity_*: bump rarity to the next tier ----
local function _upgrade_rarity(self, item_backend_ids)
    local mirror = self._backend_mirror
    local item_interface = Managers.backend:get_interface("items")
    local weapon_bid = item_backend_ids[1]
    if not weapon_bid then return {} end

    local item = item_interface:get_item_from_id(weapon_bid)
    if not item then return {} end

    local cur = item.rarity or "plentiful"
    local cur_idx = _RARITY_INDEX[cur] or 1
    local new = _RARITY_CHAIN[cur_idx + 1] or "unique"
    item.rarity = new
    if item.CustomData then item.CustomData.rarity = new end
    mirror:update_item(weapon_bid, item)
    return _result_for_modified(weapon_bid)
end

synth.upgrade_item_rarity_common = _upgrade_rarity
synth.upgrade_item_rarity_rare = _upgrade_rarity
synth.upgrade_item_rarity_exotic = _upgrade_rarity
synth.upgrade_item_rarity_unique = _upgrade_rarity

-- ---- Shuffle-bag reroll: cycle through every property combo (or trait) before
-- repeating any. State is persisted per-backend_id in the same `_forged_weapons`
-- save so closing/reopening the game doesn't reset the bag.
local function _shuffle_pick(saved_indices, pool_size)
    saved_indices = saved_indices or {}
    local seen = {}
    for _, idx in ipairs(saved_indices) do seen[idx] = true end
    local available = {}
    for i = 1, pool_size do
        if not seen[i] then available[#available + 1] = i end
    end
    if #available == 0 then
        saved_indices = {}
        available = {}
        for i = 1, pool_size do available[i] = i end
    end
    local picked = available[math.random(1, #available)]
    saved_indices[#saved_indices + 1] = picked
    return picked, saved_indices
end

-- The weapon's bid can sit at either end of `item_backend_ids` depending on
-- which UI invoked the recipe:
--   * `CraftPageRollProperties` (Keep forge) prepends the weapon and appends
--     materials → weapon at index 1.
--   * `HeroWindowItemCustomization` (gear-icon menu) prepends materials and
--     appends the weapon at the end (`hero_window_item_customization.lua:2453-2455`).
-- v0.7.21 only handled index 1 → gear-menu rerolls got a material bid (or
-- nil in modded realm) → `master.trait_table_name` was nil → "Reroll: no
-- trait pool for nil" echo and the item ended up with empty traits/props.
-- Fix: scan all bids, return the first one whose ItemMasterList entry has
-- a slot_type in the weapon/jewellery set.
local _WEAPON_SLOT_TYPES_REROLL = { melee = true, ranged = true, ring = true, necklace = true, trinket = true }

local function _resolve_weapon_input(item_interface, item_backend_ids)
    if not item_backend_ids then return nil, nil end
    for _, bid in ipairs(item_backend_ids) do
        if bid then
            local item = item_interface:get_item_from_id(bid)
            local item_data = item and item.data
            if item_data and _WEAPON_SLOT_TYPES_REROLL[item_data.slot_type] then
                return bid, item
            end
        end
    end
    return nil, nil
end

-- =========================================================================
-- Forge freedom toggles (v0.8.44-dev): two VMF checkboxes widen what the forge
-- will roll / offer onto a craft.
--   * allow_cw_traits          — surface the Chaos Wastes / deus "boon" traits
--                                 (crafting_disabled) the base forge drops.
--   * allow_any_trait_property — pool EVERY trait and property across all slot
--                                 types onto any item. Supersedes allow_cw_traits.
-- Both are read LIVE at roll time (never cached) so weapon_tweaker's runtime
-- WeaponTraits/WeaponProperties mutation is always reflected — same contract as
-- the CONTRACT-WITH-WEAPON_TWEAKER note on _reroll_traits below.
-- =========================================================================

-- Union of every property combo (`.exotic` tier) across all property tables.
-- Each combo is an array of property keys, appended verbatim (a duplicate combo
-- only biases the shuffle slightly; harmless).
local function _cim_all_property_combos()
    local WP = rawget(_G, "WeaponProperties")
    local combinations = WP and WP.combinations
    if type(combinations) ~= "table" then return nil end
    local out = {}
    for _, tbl in pairs(combinations) do
        local exotic = type(tbl) == "table" and tbl.exotic
        if type(exotic) == "table" then
            for _, combo in ipairs(exotic) do
                out[#out + 1] = combo
            end
        end
    end
    return out
end

-- Property-combo pool to roll from for `master`. allow_any_trait_property ON →
-- every property, any slot type; otherwise the item's own `.exotic` pool
-- (unchanged behavior). Properties are unaffected by allow_cw_traits.
local function _cim_property_pool_for(master)
    if mod:get("allow_any_trait_property") then
        local all = _cim_all_property_combos()
        if all and #all > 0 then return all end
    end
    local WP = rawget(_G, "WeaponProperties")
    local prop_table = master and master.property_table_name
    return WP and WP.combinations and prop_table and WP.combinations[prop_table]
           and WP.combinations[prop_table].exotic
end

-- Deduped list of every individual property KEY across all property combos
-- (combos hold 1-2 keys each). Used by the Athanor freedom injection, which
-- wants one bubble-row per distinct property, not per combo.
local function _cim_all_property_keys()
    local combos = _cim_all_property_combos()
    if not combos then return {} end
    local seen, out = {}, {}
    for _, combo in ipairs(combos) do
        for _, k in ipairs(combo) do
            if k and not seen[k] then seen[k] = true; out[#out + 1] = k end
        end
    end
    return out
end
mod._cim_all_property_keys = _cim_all_property_keys  -- Athanor injection + RT

-- ---- reroll_weapon_properties / reroll_jewellery_properties ----
local function _reroll_properties(self, item_backend_ids)
    local mirror = self._backend_mirror
    local item_interface = Managers.backend:get_interface("items")
    local weapon_bid, item = _resolve_weapon_input(item_interface, item_backend_ids)
    if not weapon_bid or not item then
        mod:warning("[cim] Reroll: no weapon found in inputs " .. tostring(#(item_backend_ids or {})))
        return {}
    end

    local master_key = item.key or item.ItemId
    local master = master_key and rawget(ItemMasterList, master_key)
    local pool = _cim_property_pool_for(master)
    if not pool or #pool == 0 then
        mod:echo("[cim] Reroll: no property combos for "
                 .. tostring(master and master.property_table_name))
        return {}
    end

    local saved = mod._cim_get_craft and mod._cim_get_craft(weapon_bid)
    local picked_idx, new_seen = _shuffle_pick(saved and saved.rerolled_props_indices, #pool)
    local combo = pool[picked_idx]

    local new_props = {}
    for _, pkey in ipairs(combo) do new_props[pkey] = _safe_property_value(pkey) end

    item.properties = new_props
    if item.CustomData then
        local cjson_mod = rawget(_G, "cjson")
        if cjson_mod then item.CustomData.properties = cjson_mod.encode(new_props) end
    end
    mirror:update_item(weapon_bid, item)

    if saved then
        saved.properties = new_props
        saved.rerolled_props_indices = new_seen
        if mod._cim_persist_crafts then mod._cim_persist_crafts() end
    end

    mod:echo("[cim] Rerolled props (" .. #new_seen .. "/" .. #pool .. " combos seen): " ..
             table.concat(combo, ", "))
    return _result_for_modified(weapon_bid)
end

synth.reroll_weapon_properties = _reroll_properties
synth.reroll_jewellery_properties = _reroll_properties

-- ---- reroll_weapon_traits / reroll_jewellery_traits ----
-- CONTRACT WITH weapon_tweaker: this function reads the trait pool from
-- `WeaponTraits.combinations[master.trait_table_name]` at roll time. Do NOT
-- inline a hardcoded trait list or pre-filter the pool elsewhere — weapon_tweaker
-- mutates that table in place when the user toggles trait checkboxes (adventure
-- and Chaos Wastes), and any layer of indirection breaks the toggle. Same
-- contract applies to `_make_craft_synth` further down.
--
-- The ONE allowed filter — mirror official's forge gate. Official's trait reroll
-- (HeroWindowItemCustomization, hero_window_item_customization.lua:2259) only
-- offers a trait when `not WeaponTraits.traits[key].crafting_disabled`. The
-- deus / Chaos-Wastes BOON traits — deus_extra_shot (the "two arrows" extra-shot
-- trait), shield_splinters, piercing_projectiles, deus_crit_chain_lightning,
-- deus_ranged_crit_explosion — all set crafting_disabled=true and live in deus
-- pools like `ranged_energy` (the Moonfire Bow's trait_table_name). Without this
-- gate CIM offered them on craftable weapons (illegal in official). This filters
-- a COPY at roll time (never mutates WeaponTraits.combinations), so wt's live
-- adventure<->CW toggle is untouched; it just drops the same boon-only traits the
-- official forge drops. (Sienna staves + Bardin drakefire use the clean vanilla
-- `ranged_heat` pool, so they have nothing to drop — only deus-pool weapons change.)
local function _craftable_trait_pool(pool)
    local WT = rawget(_G, "WeaponTraits")
    local traits = WT and WT.traits
    if not traits or type(pool) ~= "table" then return pool end
    local out = {}
    for _, entry in ipairs(pool) do
        local tkey  = entry and entry[1]
        local tdata = tkey and traits[tkey]
        if tkey and not (tdata and tdata.crafting_disabled) then
            out[#out + 1] = entry
        end
    end
    -- Safety: a pool that filtered to empty (all crafting_disabled) falls back to
    -- the raw pool rather than handing the caller an empty pool (would break reroll).
    if #out == 0 then return pool end
    return out
end

-- Chaos Wastes / deus "boon" trait entries eligible for one exact weapon slot.
-- Vanilla encodes eligibility in the owning combination category, not on the
-- trait row itself. Shared boons remain shared because vanilla lists them in
-- both a melee and ranged category. Built live so wt mutations are reflected.
local function _cim_cw_trait_entries(slot_type)
    local WT = rawget(_G, "WeaponTraits")
    local combinations = WT and WT.combinations
    local traits = WT and WT.traits
    local policy = mod._cim_trait_slot_policy
    if type(combinations) ~= "table" or type(traits) ~= "table"
        or type(policy) ~= "table" or type(policy.category_matches_slot) ~= "function" then
        return {}
    end
    local seen, out = {}, {}
    for cat, pool in pairs(combinations) do
        if policy.category_matches_slot(cat, slot_type) and type(pool) == "table" then
            for _, entry in ipairs(pool) do
                local k = entry and entry[1]
                if k and not seen[k] then
                    local tdata = traits[k]
                    if tdata then
                        seen[k] = true
                        out[#out + 1] = { k }
                    end
                end
            end
        end
    end
    return out
end

-- Union of every trait combo across all trait tables (deduped by trait key).
local function _cim_all_trait_entries()
    local WT = rawget(_G, "WeaponTraits")
    local combinations = WT and WT.combinations
    if type(combinations) ~= "table" then return {} end
    local seen, out = {}, {}
    for _, pool in pairs(combinations) do
        if type(pool) == "table" then
            for _, entry in ipairs(pool) do
                local k = entry and entry[1]
                if k and not seen[k] then
                    seen[k] = true
                    out[#out + 1] = { k }
                end
            end
        end
    end
    return out
end

-- Trait pool to roll from for `master`, honoring both toggles:
--   allow_any_trait_property → every trait, any slot type (widest).
--   allow_cw_traits          → own pool + CW traits for the exact slot family.
--   (neither)                → the item's own pool, boon-filtered (base behavior).
local function _cim_trait_pool_for(master)
    local WT = rawget(_G, "WeaponTraits")
    local combinations = WT and WT.combinations
    if type(combinations) ~= "table" then return nil end

    if mod:get("allow_any_trait_property") then
        local all = _cim_all_trait_entries()
        if #all > 0 then return all end
    end

    local trait_table = master and master.trait_table_name
    local base = trait_table and combinations[trait_table]
    if not base then return nil end

    if mod:get("allow_cw_traits") then
        local seen, out = {}, {}
        local function _add(list)
            for _, entry in ipairs(list) do
                local k = entry and entry[1]
                if k and not seen[k] then seen[k] = true; out[#out + 1] = entry end
            end
        end
        _add(base)                                      -- own pool (boons kept)
        _add(_cim_cw_trait_entries(master.slot_type))   -- exact-slot CW traits
        return out
    end

    return _craftable_trait_pool(base)  -- default: boon-filtered, unchanged
end

-- Exposed for /cim_regression_test (freedom-toggle pool invariants).
mod._cim_cw_trait_entries   = _cim_cw_trait_entries
mod._cim_all_trait_entries  = _cim_all_trait_entries
mod._cim_trait_pool_for     = _cim_trait_pool_for
mod._cim_property_pool_for  = _cim_property_pool_for

local function _reroll_traits(self, item_backend_ids)
    local mirror = self._backend_mirror
    local item_interface = Managers.backend:get_interface("items")
    -- Same scan-for-weapon pattern as _reroll_properties — see comment there.
    local weapon_bid, item = _resolve_weapon_input(item_interface, item_backend_ids)
    if not weapon_bid or not item then
        mod:warning("[cim] Reroll: no weapon found in inputs " .. tostring(#(item_backend_ids or {})))
        return {}
    end

    local master_key = item.key or item.ItemId
    local master = master_key and rawget(ItemMasterList, master_key)
    local pool = _cim_trait_pool_for(master)
    if not pool or #pool == 0 then
        mod:echo("[cim] Reroll: no trait pool for "
                 .. tostring(master and master.trait_table_name))
        return {}
    end

    local saved = mod._cim_get_craft and mod._cim_get_craft(weapon_bid)
    local picked_idx, new_seen = _shuffle_pick(saved and saved.rerolled_trait_indices, #pool)
    local entry = pool[picked_idx]
    local trait_key = entry and entry[1]
    if not trait_key then return {} end

    local new_traits = { trait_key }
    item.traits = new_traits
    if item.CustomData then
        local cjson_mod = rawget(_G, "cjson")
        if cjson_mod then item.CustomData.traits = cjson_mod.encode(new_traits) end
    end
    mirror:update_item(weapon_bid, item)

    if saved then
        saved.traits = new_traits
        saved.trait = trait_key
        saved.rerolled_trait_indices = new_seen
        if mod._cim_persist_crafts then mod._cim_persist_crafts() end
    end

    mod:echo("[cim] Rerolled trait (" .. #new_seen .. "/" .. #pool .. " seen): " .. trait_key)
    return _result_for_modified(weapon_bid)
end

synth.reroll_weapon_traits = _reroll_traits
synth.reroll_jewellery_traits = _reroll_traits

-- ---- craft_random_item / craft_weapon / craft_jewellery ----
-- Purely additive (creates a new item with a fresh backend_id) — same pattern the
-- Athanor uses, so PlayFab tolerates it as an unknown GUID. The input slot item is
-- left untouched (vanilla would consume it, but we'd hit the anti-tamper kick).

local function _local_career_name()
    local player = Managers.player and Managers.player:local_player()
    if not player then return nil end
    local profile = SPProfiles[player:profile_index()]
    if not profile then return nil end
    local career = profile.careers[player:career_index()]
    return career and career.name
end

-- issue 390: a craft whose input key is a character_weapon_variants (CWV)
-- variant needs a backend_id that CWV's render-rescue hooks recognize.
-- CWV's clone inherits the BASE weapon's `name`, so the vanilla equip path
-- (`item_name = item_data.name` -> `ItemMasterList[item_name]`, e.g.
-- world_hero_previewer.lua:674) re-resolves item_data to the BASE entry and
-- returns the base mesh + inherited attachments (Nordland -> Bretonnian
-- sword, rapier keeps the Saltzpyre pistol). CWV compensates via a set of
-- hooks keyed on the `cwv_<key>_NNN` backend_id pattern (get_item_units units
-- override, _resolve_cwv_def grip transforms, illusion-picker filter). A bare
-- `Application.guid()` backend_id matches none of them, so the crafted copy is
-- left rendering the base weapon. We detect CWV keys and mint a matching
-- backend_id below. See the CHANGELOG 0.8.52-dev entry.
local function _is_cwv_craft_key(item_key)
    if type(item_key) ~= "string" or item_key:sub(1, 4) ~= "cwv_" then return false end
    local entry = rawget(ItemMasterList, item_key)
    return entry ~= nil and entry.cwv_variant == true
end

-- Mint a `cwv_<key>_NNN` backend_id in the 100..999 instance band. CWV's own
-- items live at _001.._00N (N = def.instances, currently max 2), so starting
-- at 100 never collides with a native CWV registration. Uniqueness across
-- cim crafts (incl. restored ones) is guaranteed by scanning the persisted
-- craft table. Returns nil if the band is exhausted (caller falls back to a
-- guid; the cim-side units rescue below still fixes the mesh).
local function _mint_cwv_backend_id(item_key)
    for i = 100, 999 do
        local bid = string.format("%s_%03d", item_key, i)
        if not (mod._cim_get_craft and mod._cim_get_craft(bid)) then
            return bid
        end
    end
    return nil
end

local function _make_craft_synth(allowed_slots)
    return function(self, item_backend_ids)
        local career_name = _local_career_name()
        if not career_name then
            mod:echo("[cim] craft: no local career resolved")
            return nil
        end

        -- Resolve the craft target. The player drops a weapon into the recipe
        -- slot — typically a "blacksmith's weapon" (a starter weapon at default
        -- rarity, e.g. an Imperial Longsword the character started with). We
        -- clone whatever the player dropped, regardless of rarity. The vanilla
        -- recipe randomized within the slot type — modded users want to choose.
        local item_key
        local slots = allowed_slots
        if item_backend_ids[1] then
            local item_interface = Managers.backend:get_interface("items")
            local input_item = item_interface:get_item_from_id(item_backend_ids[1])
            local input_data = input_item and input_item.data

            -- Sanity-gate: the recipe is filtered to only show items whose
            -- slot_type is in the recipe's `allowed_slots`, but Athanor / the
            -- Craft Item recipe's empty-slot click can hand us an item with
            -- slot_type = "crafting_material" (and friends) that DID slip
            -- through the filter. Cloning that produces a "modded crafting
            -- material scrap" that the rest of cim's inventory logic can't
            -- handle. Refuse if the slot_type isn't in our recipe's allowed
            -- set OR in the universal craftable set.
            if input_data and input_data.slot_type then
                local st = input_data.slot_type
                local ok = allowed_slots[st] or _CRAFTABLE_SLOT_TYPES[st]
                if not ok then
                    mod:warning("[cim] Cannot craft " .. tostring(input_item.key or "?") ..
                        " — slot_type '" .. tostring(st) .. "' isn't a weapon/jewellery slot.")
                    return nil
                end
                slots = { [st] = true }
            end

            -- Use whatever weapon the player put in the slot. Default-rarity
            -- placeholders (starter weapons) ARE the player's choice — they
            -- represent a specific weapon type (Imperial Longsword, halberd,
            -- etc), not just "any melee weapon".
            if input_item then
                item_key = input_item.key or input_item.ItemId
                if not item_key and input_data then
                    item_key = input_data.key or input_data.name
                end
                if item_key then
                    mod:echo("[cim] Cloning chosen weapon: " .. tostring(item_key))
                end
            end
        end

        if not item_key then
            local eligible = {}
            local real_names = _cim_real_display_names()
            for key, data in pairs(ItemMasterList) do
                if slots[data.slot_type]
                   and data.can_wield and table.contains(data.can_wield, career_name)
                   and data.item_type ~= "weapon_skin"
                   and data.rarity ~= "magic" and data.rarity ~= "promo"
                   and not _item_requires_unowned_dlc(key)
                   and not _cim_versus_shadowed(data, real_names) then
                    eligible[#eligible + 1] = key
                end
            end

            if #eligible == 0 then
                mod:warning("[cim] No eligible items for career " .. career_name)
                return nil
            end

            item_key = eligible[math.random(1, #eligible)]
        end

        -- Property / trait prefill is OPT-IN as of v0.7.24 (default off). When
        -- the user wants a bare 300-power template they can roll on, leave
        -- both tables empty here and let the inventory tooltip show "no
        -- properties / no trait" until they reroll. When the prefill toggle
        -- is enabled, restore the legacy behavior of seeding 2 max-value
        -- properties + 1 random trait. (Feedback #3.)
        local rolled_props = {}
        local rolled_traits = {}
        if mod:get("prefill_random_properties") then
            local master = rawget(ItemMasterList, item_key)
            if master then
                -- Same freedom-toggle-aware pools the reroll path uses, so a
                -- prefilled craft honors allow_cw_traits / allow_any_trait_property.
                local prop_pool = _cim_property_pool_for(master)
                if prop_pool and #prop_pool > 0 then
                    local combo = prop_pool[math.random(1, #prop_pool)]
                    if combo then
                        for _, pkey in ipairs(combo) do
                            rolled_props[pkey] = _safe_property_value(pkey)
                        end
                    end
                end

                local trait_pool = _cim_trait_pool_for(master)
                if trait_pool and #trait_pool > 0 then
                    local pick = trait_pool[math.random(1, #trait_pool)]
                    local tkey = pick and pick[1]
                    if tkey then rolled_traits[#rolled_traits + 1] = tkey end
                end
            end
        end

        local power_level = _cim_base_power()
        local cjson_mod = rawget(_G, "cjson")
        local custom_data = {
            power_level = tostring(power_level),
            rarity = "modded",
        }
        if cjson_mod then
            custom_data.properties = cjson_mod.encode(rolled_props)
            custom_data.traits = cjson_mod.encode(rolled_traits)
        end

        -- issue 390: CWV variant crafts get a `cwv_<key>_NNN` backend_id so the
        -- CWV render-rescue hooks recognize them; everything else keeps a fresh
        -- guid. Falls back to a guid if the instance band is exhausted.
        local backend_id
        if _is_cwv_craft_key(item_key) then
            backend_id = _mint_cwv_backend_id(item_key)
        end
        backend_id = backend_id or Application.guid()
        local item = {
            ItemId = item_key,
            ItemInstanceId = backend_id,
            CustomData = custom_data,
        }

        local ok, err = pcall(self._backend_mirror.add_item, self._backend_mirror, backend_id, item)
        if not ok then
            -- v0.7.52-dev: mod:warning (was mod:echo, chat-suppressed) +
            -- comprehensive synth-result probe so failures are visible.
            mod:warning("[cim] add_item FAILED for " .. item_key .. ": " .. tostring(err))
            if mod._cim_autodump_craft_synth_result then
                local weapon_data_fail = {
                    item_key = item_key,
                    properties = rolled_props,
                    traits = rolled_traits,
                    power_level = power_level,
                    rarity = "modded",
                    via_mirror = true,
                }
                pcall(mod._cim_autodump_craft_synth_result, "standard_forge_FAIL",
                    career_name, item_key, backend_id, weapon_data_fail, false, err)
            end
            return nil
        end

        -- Persist so the item survives a game restart. Same save layer as the
        -- Athanor — registered with `via_mirror = true` so `_athanor_inject_all`
        -- re-creates it via backend_mirror:add_item on next session.
        local weapon_data = {
            item_key = item_key,
            properties = rolled_props,
            traits = rolled_traits,
            power_level = power_level,
            rarity = "modded",
            via_mirror = true,
        }
        if mod._cim_register_craft then
            mod._cim_register_craft(backend_id, weapon_data)
        end

        -- Verify the item is actually in the mirror after add_item
        local item_interface = Managers.backend:get_interface("items")
        local stored = item_interface and item_interface:get_item_from_id(backend_id)
        local stored_key = stored and (stored.key or (stored.data and stored.data.key)) or "<nil>"
        local stored_rarity = stored and stored.rarity or "<nil>"
        mod:echo("[cim] Crafted " .. item_key .. " (key=" .. tostring(stored_key) .. " rarity=" .. tostring(stored_rarity) .. " bid=" .. tostring(backend_id) .. ")")

        -- v0.7.52-dev: comprehensive post-craft diagnostic + 2-frame-later
        -- visibility check. Same probe as the Athanor `_equip_item` path so
        -- both craft routes produce the same diagnostic trail.
        if mod._cim_autodump_craft_synth_result then
            pcall(mod._cim_autodump_craft_synth_result, "standard_forge_synth",
                career_name, item_key, backend_id, weapon_data, true, nil)
        end

        -- issue 390: trace the CWV crafted copy's resolved units. The CWV entry
        -- carries the variant mesh (and nils the inherited left-hand attachment
        -- via no_left_hand); the BASE entry the vanilla equip path re-resolves
        -- to via `item_data.name` carries the wrong mesh + attachments. Logging
        -- both makes the divergence (and whether the rescue must bridge it)
        -- visible. Always-on in dev; fires only on a craft action.
        if _is_cwv_craft_key(item_key) then
            do
                local cwv_entry = rawget(ItemMasterList, item_key)
                local base_entry = cwv_entry and cwv_entry.name and rawget(ItemMasterList, cwv_entry.name)
                printf("[cim:390] crafted CWV key=%s bid=%s base_name=%s | cwv rhu=%s lhu=%s | BASE rhu=%s lhu=%s",
                    tostring(item_key), tostring(backend_id),
                    tostring(cwv_entry and cwv_entry.name),
                    tostring(cwv_entry and cwv_entry.right_hand_unit),
                    tostring(cwv_entry and cwv_entry.left_hand_unit),
                    tostring(base_entry and base_entry.right_hand_unit),
                    tostring(base_entry and base_entry.left_hand_unit))
            end
        end

        return { { backend_id, [3] = 1 } }
    end
end

synth.craft_random_item = _make_craft_synth({ melee = true, ranged = true, trinket = true, ring = true, necklace = true })
synth.craft_weapon      = _make_craft_synth({ melee = true, ranged = true })
synth.craft_jewellery   = _make_craft_synth({ trinket = true, ring = true, necklace = true })
-- Per-slot jewelry synths (feedback #6). VT2 slot_type mapping is:
--   slot_necklace -> "necklace"  (Apothecary's Shield etc.)
--   slot_ring     -> "ring"      (charms — Decanter, Barkskin, etc.)
--   slot_trinket  -> "trinket"   (trinkets — Healer's Kit Strap, Stamina Insignia)
-- Exposed via chat commands below so the user can pick exactly which jewelry
-- slot to craft instead of relying on a vanilla recipe to pick at random.
synth.craft_necklace = _make_craft_synth({ necklace = true })
synth.craft_charm    = _make_craft_synth({ ring = true })
synth.craft_trinket  = _make_craft_synth({ trinket = true })

-- Issue 407: expose the synth-name set so /cim_regression_test can verify every
-- recipe the console craft-item resolver derives (craft_weapon / craft_necklace /
-- craft_charm / craft_trinket) actually has a live synth registered. A boolean
-- snapshot, not the closures, so the test can't accidentally invoke a synth.
mod._cim407_synth_names_for_rt = {}
for _name in pairs(synth) do mod._cim407_synth_names_for_rt[_name] = true end

-- ============================================================
-- Direct-craft chat commands (feedback #6)
-- ============================================================
-- The vanilla `craft_jewellery` recipe always rolls a random jewelry slot.
-- Users who want a specific slot can drop a slot-specific blacksmith template
-- in the standard craft UI, but the UI affordance for "craft this exact type"
-- isn't obvious. These chat commands skip the UI entirely and craft one item
-- of the chosen jewelry type for the local player's current career, applying
-- the same `base_power_level` setting and `prefill_random_properties` toggle
-- as the UI path.
-- v0.7.57-dev: exposed as mod._cim_craft_via_synth for the Athanor overview
-- jewelry buttons (defined in crafting_in_modded_dev.lua). Same direct-craft
-- path the standard-forge accessory buttons + `/cim_craft_*` commands use.
local function _craft_via_synth(slot_filter, friendly_label)
    local crafting = Managers.backend and Managers.backend:get_interface("crafting")
    if not crafting then
        mod:warning("[cim] crafting interface not ready")
        return
    end
    -- Briefly flip the active flag so the silent craft fires through the same
    -- code paths the UI craft uses (DLC gating, slot validation, persistence).
    local was_active = mod._cim_standard_forge_active
    mod._cim_standard_forge_active = true
    local synth_fn = _make_craft_synth(slot_filter)
    local result = synth_fn(crafting, {}, nil, nil)
    mod._cim_standard_forge_active = was_active
    if result and result[1] then
        mod:echo(string.format("[cim] Crafted %s.", friendly_label))
        if Managers.backend and Managers.backend.dirtify_interfaces then
            pcall(Managers.backend.dirtify_interfaces, Managers.backend)
        end
    end
end

mod._cim_craft_via_synth = _craft_via_synth

mod:command("cim_craft_necklace", "Craft one modded necklace for your current career", function()
    _craft_via_synth({ necklace = true }, "necklace")
end)
mod:command("cim_craft_charm", "Craft one modded charm for your current career", function()
    _craft_via_synth({ ring = true }, "charm")
end)
mod:command("cim_craft_trinket", "Craft one modded trinket for your current career", function()
    _craft_via_synth({ trinket = true }, "trinket")
end)

-- ============================================================
-- Synthetic "blacksmith's template" items
-- ============================================================
-- Vanilla's `can_craft_with` filter (backend_interface_common.lua:498) only
-- matches `rarity == "default"` items. In modded realm the player doesn't have
-- a default-rarity template for every weapon family — career-level unlocks
-- gate which starter weapons exist, and CWV / mod-added weapons never get
-- one. To make the Craft Item recipe usable for ALL career-eligible weapons,
-- we inject a synthetic default-rarity template per item_type into the
-- recipe's inventory list, and teach `get_item_from_id` to resolve them back
-- to a craftable input.
--
-- Templates are not in the backend mirror. They never leak into the regular
-- inventory tab (different filter), and clicking craft on one feeds it to
-- `_make_craft_synth` as the input — which clones its `key` into a fresh
-- modded-rarity item via `add_item`. The template itself is never consumed
-- or mutated.

-- _CRAFTABLE_SLOT_TYPES is declared at the top of the file (near _is_active)
-- so `_make_craft_synth`'s closure can reference it without a forward-ref bug.
local _template_cache = {}

local function _build_template_cache()
    _template_cache = {}
    if not ItemMasterList then return end
    local career_name = _local_career_name()
    if not career_name then return end

    -- Templates inherit the player's chosen base power level so the craft
    -- preview ("X power" widget) shows what the resulting item will actually
    -- be (feedback #9). Pre-v0.7.24 this was hardcoded 5, which produced
    -- "5 power" in the preview while the craft result was 300.
    local base_power = _cim_base_power()
    local real_names = _cim_real_display_names()
    for key, data in pairs(ItemMasterList) do
        if type(data) == "table"
            and data.slot_type and _CRAFTABLE_SLOT_TYPES[data.slot_type]
            and data.can_wield and table.contains(data.can_wield, career_name)
            and data.item_type ~= "weapon_skin"
            and data.rarity ~= "magic" and data.rarity ~= "promo"
            and not _item_requires_unowned_dlc(key)
            and not _cim_versus_shadowed(data, real_names) then
            local bid = "cim_template_" .. key
            _template_cache[bid] = {
                backend_id = bid,
                cim_acquisition_template = true,
                cim_acquisition_key = key,
                key = key,
                ItemId = key,
                ItemInstanceId = bid,
                rarity = "default",
                data = data,
                properties = {},
                traits = {},
                power_level = base_power,
                CustomData = {
                    power_level = tostring(base_power),
                    rarity = "default",
                    properties = "{}",
                    traits = "[]",
                },
            }
        end
    end
end

mod._cim_template_lookup = function(backend_id)
    return _template_cache[backend_id]
end

-- Exposed for the consolidated `on_enter` hook above to invoke at call time.
mod._cim_rebuild_template_cache = _build_template_cache

-- Called from the shared `get_filtered_items` hook in crafting_in_modded.lua
-- once it's finished its modded-only filtering pass. Returns the same items
-- table with a synthetic template appended for every craftable weapon KEY not
-- already represented by a real entry.
--
-- issue 390: this used to dedup on `item_type`, appending only ONE template
-- per item_type in non-deterministic pairs() order. CWV variant families share
-- a single item_type across members (Recruit / Black Guard / base longsword all
-- `cwv_imperial_longsword`), so only one random member was craftable. Keying on
-- the item `key` makes every distinct variant individually craftable and
-- deterministic. skin_only CWV defs (e.g. cwv_es_longsword_nordland) are never
-- registered in ItemMasterList by CWV, so _build_template_cache never mints a
-- template for them -- they stay correctly non-craftable (get the look via the
-- real family member + the Nordland illusion in the cosmetic picker).
mod._cim390_inject_key_keyed = true
-- #592: CWV contributes definitions, never owned blacksmith items. Therefore
-- CIM's one key-keyed synthetic template is the sole acquisition selector.
mod._cim592_cwv_registration_only = true
mod._cim_inject_templates = function(items, filter)
    if not _is_active() then return items end
    if type(filter) ~= "string" or not filter:find("can_craft_with", 1, true) then
        return items
    end
    if not next(_template_cache) then _build_template_cache() end

    return template_selector.inject(items, _template_cache)
end

-- The Craft Item recipe's synth (`_make_craft_synth`) looks up the input via
-- `item_interface:get_item_from_id(bid)`. Resolve template bids back to their
-- cached entry so the synth reads `.key` and clones the right weapon.
mod:hook("BackendInterfaceItemPlayfab", "get_item_from_id", function(func, self, backend_id)
    local tpl = _template_cache[backend_id]
    if tpl then return tpl end
    return func(self, backend_id)
end)

-- ============================================================
-- issue 390: units rescue for cim-crafted CWV variants
-- ============================================================
-- The vanilla equip/preview path re-resolves item_data from `item_data.name`
-- (backend_utils / world_hero_previewer:674), which for a CWV clone is the
-- BASE weapon name -> ItemMasterList[base] -> base mesh + inherited
-- attachments. CWV's own get_item_units override forces the variant units back
-- in, but it only fires for backend_ids matching `cwv_<key>_NNN`. We now mint
-- exactly that pattern (_make_craft_synth), so CWV's hook can rescue our crafts
-- once its match pattern is widened past the literal `_001`. This hook is the
-- cim-side safety net that forces the variant units regardless, so the MESH is
-- correct even before that CWV-side widen lands. Grip/scale transforms still
-- come from CWV's create_equipment hook (which also keys on the backend_id
-- pattern) -- those need the widened pattern to apply.
--
-- Pre-flight grep confirmed cim does not otherwise hook (BackendUtils,
-- get_item_units); it only CALLS it. VMF chains this cim hook after CWV's own
-- (different mod), so we see (and, idempotently, re-affirm) CWV's result.
if rawget(_G, "BackendUtils") then
    mod:hook(BackendUtils, "get_item_units", function(func, item_data, backend_id, skin, career_name)
        local result = func(item_data, backend_id, skin, career_name)
        if type(result) ~= "table" or type(backend_id) ~= "string" then return result end
        local craft = mod._cim_get_craft and mod._cim_get_craft(backend_id)
        local ckey = craft and craft.item_key
        if type(ckey) ~= "string" or ckey:sub(1, 4) ~= "cwv_" then return result end
        -- A skin/illusion took effect during resolution -> its per-hand units
        -- already won; don't trample the user's chosen look.
        if result.skin and result.skin ~= "" then return result end
        local cwv_entry = rawget(ItemMasterList, ckey)
        if not cwv_entry then return result end
        -- Force the variant's own per-hand meshes. Matches CWV's own rescue
        -- (character_weapon_variants.lua get_item_units hook): a nil left unit
        -- (no_left_hand variants like the rapier) correctly drops the inherited
        -- base attachment.
        result.right_hand_unit = cwv_entry.right_hand_unit
        result.left_hand_unit = cwv_entry.left_hand_unit
        return result
    end)
    mod._cim390_units_rescue_installed = true
end

-- Diagnostic: list every recently-added (post-load) inventory item so we can
-- see whether crafted items landed in the mirror but failed to surface in the UI.
mod:command("craft_recent", "List newly-added items in the backend mirror", function()
    local mirror = Managers.backend and Managers.backend:get_backend_mirror()
    if not mirror or not mirror._inventory_items then
        mod:warning("[cim] backend mirror not ready")
        return
    end
    local item_interface = Managers.backend:get_interface("items")
    local count = 0
    for bid, item in pairs(mirror._inventory_items) do
        local key = (item and item.key) or (item and item.data and item.data.key) or "<nil>"
        local rarity = item and item.rarity or "<nil>"
        local slot = item and item.data and item.data.slot_type or "<nil>"
        local can_wield = item and item.data and item.data.can_wield
        local cw = "<nil>"
        if type(can_wield) == "table" then
            cw = table.concat(can_wield, ",")
        end
        if ItemHelper and ItemHelper.is_new_backend_id and ItemHelper.is_new_backend_id(bid) then
            count = count + 1
            mod:info("[cim] [%d] bid=%s key=%s rarity=%s slot=%s can_wield=%s", count, tostring(bid), tostring(key), tostring(rarity), tostring(slot), cw)
            if count <= 20 then
                mod:echo(string.format("[%d] %s rarity=%s slot=%s", count, tostring(key), tostring(rarity), tostring(slot)))
            end
        end
    end
    mod:echo("[cim] " .. count .. " new-flagged items in mirror (full data in log)")
end)

-- ============================================================
-- craft() short-circuit: replace PlayFab roundtrip with local synth
-- ============================================================

-- Issue 407: map a dropped item's slot_type to the cim synth recipe used when
-- the console "Craft Item" page supplies no recipe_override. Vanilla
-- craft_page_craft_item_console.lua:80-84 picks craft_weapon for melee/ranged
-- and craft_jewellery for jewelry; cim substitutes its per-slot jewelry synths
-- (craft_necklace / craft_charm / craft_trinket) so the jewelry slot is honored
-- exactly as the setup_recipe_requirements pin does. Exposed on `mod` for the
-- /cim_regression_test check (console_craft_item_nil_recipe_resolves).
mod._cim407_craft_item_recipe_for_slot = function(slot)
    if slot == "melee" or slot == "ranged" then return "craft_weapon" end
    if slot == "necklace" then return "craft_necklace" end
    if slot == "ring"     then return "craft_charm"    end
    if slot == "trinket"  then return "craft_trinket"  end
    return nil
end

mod:hook("BackendInterfaceCraftingPlayfab", "craft", function(func, self, career_name, item_backend_ids, recipe_override)
    -- Illusion-swap intercept FIRST: applies regardless of whether the
    -- standard crafting UI is open. Defined in illusion_swap.lua and
    -- wired here so we only register ONE craft hook (VMF rejects rehooks
    -- on the same class/method with "Attempting to rehook active hook").
    if mod._cim_try_illusion_apply then
        local id, recipe = mod._cim_try_illusion_apply(self, career_name, item_backend_ids, recipe_override)
        if id then return id, recipe end
    end

    if not _is_active() then
        return func(self, career_name, item_backend_ids, recipe_override)
    end

    -- Active = standard forge UI is open. NEVER fall through to the original
    -- `craft()` here — it would enqueue an `ExecuteCloudScript` PlayFab request
    -- with `send_eac_challenge = true` (playfab_request_queue.lua:44), and in
    -- modded realm the EAC client is unavailable so the response triggers
    -- `playfab_eac_error` (reason 511) → "Backend rejected the challenge response"
    -- → quit. Any unrecognized recipe is reported and silently dropped instead.
    --
    -- CRITICAL: we must return a NON-NIL (id, recipe) tuple even on the silent-
    -- drop path. `craft_page_craft_item.lua:287-336` runs the craft trigger as
    -- a press-and-hold: every frame the button hold is at progress=1.0,
    -- `parent:craft()` fires. `HeroWindowCrafting.craft` (`hero_window_crafting.lua:542-560`)
    -- checks `if craft_id then ... return true` and only on a truthy return
    -- does it set `_waiting_for_craft = true` + `:lock_input()`. On nil it
    -- returns false → press-and-hold isn't acknowledged → fires again next
    -- frame → infinite log spam ("Recipe 'nil' could not be resolved" x50/s
    -- in the user's session) and the menu wedges in a busy-craft state.
    --
    -- Fix: when we silently drop, mint a no-op craft id and stash an empty
    -- result in `_craft_requests` so `is_craft_complete(id)` immediately
    -- returns true. The UI plays its craft-complete animation, the button
    -- disables, and we move on.
    local function _silent_drop(reason_text)
        -- v0.7.50-dev: mod:warning so action-rejection feedback always reaches
        -- chat regardless of `enable_debug_logging` (v0.7.44 visibility rule).
        -- Was mod:echo, which the v0.7.38 chat-suppression patch silenced into
        -- log-only when debug was off — user perceived clicks as no-ops.
        mod:warning("[cim] " .. reason_text)
        self._last_id = (self._last_id or 0) + 1
        self._craft_requests[self._last_id] = {}
        return self._last_id, { name = "cim_noop" }
    end

    -- v0.7.50-dev: discriminate the three drop modes + dump the actual values
    -- so user reports of "many crafts failed, don't know why" are diagnosable
    -- from the warning chat alone (no need to grep the log).
    -- Always-on verbose dump on entry (gated on debug logging) for cross-call
    -- diagnosis — captures career, recipe, list length, first 3 item BIDs.
    if mod._cim_autodump_craft_attempt then
        pcall(mod._cim_autodump_craft_attempt, career_name, item_backend_ids, recipe_override)
    end
    if not recipe_override then
        -- Console/gamepad "Craft Item" page passes NO recipe: vanilla
        -- craft_page_craft_item_console.lua:325 calls `parent:craft(items)` with
        -- recipe_override=nil and relies on backend auto-detection
        -- (backend_interface_crafting_base.lua:42-50 iterates every recipe). The
        -- PC page instead passes `self._recipe_name` explicitly
        -- (craft_page_craft_item.lua:322) — which is why crafting only breaks on
        -- the console UI. cim CANNOT fall through to vanilla `func` here (it would
        -- enqueue the EAC-gated PlayFab request and kick the player), so we
        -- re-derive the craft-item recipe from the dropped item's slot_type via
        -- mod._cim407_craft_item_recipe_for_slot (mirrors vanilla
        -- setup_recipe_requirements at craft_page_craft_item_console.lua:80-84,
        -- substituting cim's per-slot jewelry synths for craft_jewellery — the
        -- same pin setup_recipe_requirements applies at standard_forge.lua:330-333).
        -- Issue 407.
        -- Resolve the dropped item's slot_type. get_item_masterlist_data
        -- internally calls self:get_item_from_id (item_playfab.lua:351), which is
        -- the method cim hooks to surface `cim_template_*` entries from
        -- _template_cache — so this resolves a synthetic template bid to its
        -- data.slot_type, exactly as the craft_attempt autodump does.
        local bid1       = item_backend_ids and item_backend_ids[1]
        local item_iface = bid1 and Managers.backend and Managers.backend:get_interface("items")
        local item_data  = item_iface and item_iface:get_item_masterlist_data(bid1)
        local slot       = item_data and item_data.slot_type
        local derived    = slot and mod._cim407_craft_item_recipe_for_slot(slot)
        if derived and synth[derived] then
            recipe_override = derived
            pcall(printf, "[cim:407] console craft-item: nil recipe resolved -> %s (bid=%s slot=%s)",
                tostring(derived), tostring(bid1), tostring(slot))
        end
    end
    if not recipe_override then
        return _silent_drop(string.format(
            "Craft dropped — no recipe selected (recipe_override=nil, career=%s, items_len=%d). " ..
            "Click a recipe tile (Craft Item / Salvage / Reroll / etc.) before pressing craft.",
            tostring(career_name),
            (item_backend_ids and #item_backend_ids) or 0))
    end
    if not item_backend_ids or not item_backend_ids[1] then
        local items_len = (item_backend_ids and #item_backend_ids) or 0
        return _silent_drop(string.format(
            "Craft dropped — no template/item picked (recipe=%s, career=%s, items_len=%d). " ..
            "Select a weapon/template in the panel before pressing craft.",
            tostring(recipe_override),
            tostring(career_name),
            items_len))
    end

    local recipe, valid_ids = self:_get_valid_recipe(item_backend_ids, recipe_override)
    if not recipe then
        return _silent_drop(string.format(
            "Recipe '%s' could not be resolved (career=%s, items_len=%d, first_bid=%s). " ..
            "Dropped to avoid EAC kick.",
            tostring(recipe_override),
            tostring(career_name),
            #item_backend_ids,
            tostring(item_backend_ids[1])))
    end

    local synth_fn = synth[recipe.name]
    if not synth_fn then
        return _silent_drop(string.format(
            "Recipe '%s' not yet implemented in modded (career=%s, items_len=%d, first_bid=%s). Dropped.",
            tostring(recipe.name),
            tostring(career_name),
            #item_backend_ids,
            tostring(item_backend_ids[1])))
    end

    self._last_id = (self._last_id or 0) + 1
    local id = self._last_id
    local result = synth_fn(self, item_backend_ids, recipe, recipe_override)
    self._craft_requests[id] = result or {}

    if Managers.backend and Managers.backend.dirtify_interfaces then
        pcall(Managers.backend.dirtify_interfaces, Managers.backend)
    end
    return id, recipe
end)

-- ============================================================
-- Defense-in-depth: drop any crafting* PlayFab request at the queue
-- ============================================================
-- Even if the craft() hook above is bypassed (e.g. another mod, or a future
-- code path), this catches every `crafting*` request before it can ever reach
-- PlayFab. The signature is `enqueue(self, request, success_callback,
-- send_eac_challenge, error_callback)` — request.FunctionName names the cloud
-- function. We only block crafting-prefixed functions to avoid disturbing
-- unrelated traffic (achievements, daily quests, etc).
mod:hook("PlayFabRequestQueue", "enqueue", function(func, self, request, success_callback, send_eac_challenge, error_callback)
    if _is_active() and request and request.FunctionName then
        local fn = request.FunctionName
        if fn == "craftingSalvage" or fn == "craftingRandomItem" or fn == "craftingSpecificItem"
           or fn == "craftingRerollProperties" or fn == "craftingRerollTraits"
           or fn == "craftingUpgradeRarity" or fn == "craftingApplySkin2"
           or fn == "craftingExtractSkin" or fn == "craftingDowngradeDust" then
            mod:info("[cim] Blocked PlayFab crafting request (%s) from reaching the EAC path", fn)
            return nil
        end
    end
    return func(self, request, success_callback, send_eac_challenge, error_callback)
end)

-- ============================================================
-- On-screen per-accessory craft buttons on the standard forge
-- ============================================================
-- The vanilla "Craft Jewellery" recipe rolls a random jewelry slot. The
-- template-drop path (above) lets the user pin a slot when they drop a
-- slot-specific blacksmith template — but discovering that affordance is hard.
-- Most players don't realize they can pick a specific accessory type via the
-- standard forge.
--
-- Fix: inject three persistent buttons (CRAFT NECKLACE / CRAFT CHARM / CRAFT
-- TRINKET) into the standard forge's empty `window_bottom` panel. Clicking
-- one fires `_craft_via_synth` for that slot directly. Visible whenever the
-- standard forge UI is open.
--
-- Mirrors the Athanor amulet button pattern (`_AMULET_SLOT_BUTTONS` +
-- `_ensure_amulet_buttons` in crafting_in_modded.lua:1106-1194). Same
-- lazy-create-then-toggle-visibility model, gated on `_cim_standard_forge_active`.
--
-- TODO followup: `HeroWindowCraftingConsole` (gamepad / inventory tab variant)
-- has a different scenegraph; mirror the buttons there in a separate pass.
local _STANDARD_FORGE_BUTTONS = {
    -- Visual left-to-right order: Necklace, Charm, Trinket.
    { x_offset = -340, slot_filter = { necklace = true }, label = "CRAFT NECKLACE", echo_name = "necklace", widget_name = "cim_std_btn_necklace" },
    { x_offset =    0, slot_filter = { ring     = true }, label = "CRAFT CHARM",    echo_name = "charm",    widget_name = "cim_std_btn_charm"    },
    { x_offset = 340,  slot_filter = { trinket  = true }, label = "CRAFT TRINKET",  echo_name = "trinket",  widget_name = "cim_std_btn_trinket"  },
}

local function _ensure_std_forge_buttons(crafting_win)
    if crafting_win._cim_std_buttons then return crafting_win._cim_std_buttons end
    local UIWidgets = rawget(_G, "UIWidgets")
    local UIWidget  = rawget(_G, "UIWidget")
    if not (UIWidgets and UIWidget and UIWidgets.create_default_button) then
        -- v0.7.55-dev: surface why buttons fail to create (once per UI session)
        if not crafting_win._cim_std_buttons_logged_miss_uiwidgets then
            crafting_win._cim_std_buttons_logged_miss_uiwidgets = true
            mod:info("[cim] std forge buttons skipped: UIWidgets/UIWidget/create_default_button missing (UIWidgets=%s UIWidget=%s create_fn=%s)",
                tostring(UIWidgets), tostring(UIWidget),
                tostring(UIWidgets and UIWidgets.create_default_button))
        end
        return nil
    end

    local widgets = crafting_win._widgets
    local widgets_by_name = crafting_win._widgets_by_name
    if not (widgets and widgets_by_name) then
        if not crafting_win._cim_std_buttons_logged_miss_widgets then
            crafting_win._cim_std_buttons_logged_miss_widgets = true
            mod:info("[cim] std forge buttons skipped: window has no _widgets (%s) or _widgets_by_name (%s) yet",
                tostring(widgets), tostring(widgets_by_name))
        end
        return nil
    end
    mod:info("[cim] std forge buttons: dependencies ready, creating now (widgets table size=%d)",
        #widgets)

    local btn_size = { 300, 70 }
    local buttons = {}
    for i, entry in ipairs(_STANDARD_FORGE_BUTTONS) do
        -- Anchor "window_bottom" is 167px tall, full-width, centered horizontally.
        -- vertical_alignment=bottom on the anchor → positive y_offset lifts the
        -- button up. y=60 centers a 70-tall button roughly in the middle of the
        -- 167-tall panel. z=10 so it renders above the bottom-edge artwork.
        local ok, def = pcall(UIWidgets.create_default_button,
            "window_bottom", btn_size, nil, nil, entry.label, 22,
            nil, "button_detail_02", nil, true)
        if not ok or not def then
            mod:info("[cim] std forge button %s create failed: %s", entry.widget_name, tostring(def))
            return nil
        end
        local ok_init, w = pcall(UIWidget.init, def)
        if not ok_init or not w then
            mod:info("[cim] std forge button %s init failed: %s", entry.widget_name, tostring(w))
            return nil
        end
        w.offset = { entry.x_offset, 60, 10 }
        w.content.visible = false
        w.content._cim_slot_filter = entry.slot_filter
        w.content._cim_echo_name   = entry.echo_name
        w.content._cim_label       = entry.label
        buttons[i] = w
        widgets[#widgets + 1] = w
        widgets_by_name[entry.widget_name] = w
    end

    crafting_win._cim_std_buttons = buttons
    mod:info("[cim] standard forge: created %d cim accessory craft buttons", #buttons)
    return buttons
end

local function _show_std_forge_buttons(crafting_win, show)
    local buttons = crafting_win._cim_std_buttons
    if not buttons then return end
    for _, w in ipairs(buttons) do
        if w and w.content then w.content.visible = show and true or false end
    end
end

local function _handle_std_forge_button_clicks(crafting_win)
    local buttons = crafting_win._cim_std_buttons
    if not buttons then return end
    for _, w in ipairs(buttons) do
        local hs = w and w.content and w.content.button_hotspot
        if hs and hs.on_release then
            hs.on_release = false  -- consume to prevent re-fire next frame
            local filter = w.content._cim_slot_filter
            local echo   = w.content._cim_echo_name
            if filter and echo then
                _craft_via_synth(filter, echo)
                if crafting_win._play_sound then
                    pcall(crafting_win._play_sound, crafting_win, "play_gui_craft_forge_button_completed")
                end
            end
        end
    end
end

-- v0.7.67-dev: DISABLED. The standard forge is a select-template-then-craft
-- flow; it doesn't need cim's per-slot accessory buttons (user, 2026-05-30).
-- Jewelry crafting lives on the Athanor accessories view (the
-- _accessory_craft_panel overlay). The _STANDARD_FORGE_BUTTONS / _ensure /
-- _show / _handle helpers stay defined (harmless, unreferenced) but the
-- per-frame driver no longer creates or shows them.
local _STD_FORGE_BTNS_ENABLED = false

-- Per-frame: lazy-build, show, and probe the buttons whenever the standard
-- forge is open. `_cim_standard_forge_active` is already toggled by the
-- HeroWindowCrafting / HeroWindowCraftingConsole on_enter/on_exit hooks above.
mod:hook_safe("HeroWindowCrafting", "update", function(self, dt, t)
    if not (_STD_FORGE_BTNS_ENABLED and _is_active()) then
        if self._cim_std_buttons then _show_std_forge_buttons(self, false) end
        return
    end
    _ensure_std_forge_buttons(self)
    _show_std_forge_buttons(self, true)
    _handle_std_forge_button_clicks(self)
end)
