-- Standard Forge presentation owner. Installed only by the private whole-Forge
-- installer, after Apply state binding and before backend recipe hooks. A true
-- return acknowledges that every presentation registration completed; a missing
-- loader, false result or fault must keep the enclosing Forge capability incomplete.
return function(deps)
local mod = deps.mod
local _is_active = deps.is_active
local _get_synth = deps.get_synth
local function _pack_results(...)
    return { n = select("#", ...), ... }
end

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
    -- #524: this MUST be a wrapping pre-hook. Both vanilla crafting windows
    -- call `_change_recipe_page` from inside on_enter, and that page asks the
    -- backend for `can_craft_with` rows immediately. A hook_safe callback runs
    -- only after the original returns, which made every synthetic Blacksmith
    -- selector miss the initial page build (all 34 CWV definitions existed,
    -- but none could appear). Activate and rebuild before vanilla enters; keep
    -- diagnostics after it so their widget inspection still sees complete UI.
    mod:hook(klass, "on_enter", function(func, self, ...)
        mod._cim_standard_forge_active = true
        if mod._cim_rebuild_template_cache then
            mod._cim_rebuild_template_cache()
        end
        local results = _pack_results(func(self, ...))
        -- Debug autodump (no-op unless debug_mode setting is ON). Single
        -- consolidated callback per (class, method) -- VMF silently drops a
        -- sibling hook registration. See feedback_vmf_hook_safe_no_chain.
        if mod._cim_autodump_forge_open then
            pcall(mod._cim_autodump_forge_open, class_for_dump, self)
        end
        return unpack(results, 1, results.n)
    end)
    mod:hook_safe(klass, "on_exit", function(self)
        local owner = mod._cim_illusion_apply_presentation_owner
        if class_for_dump == "HeroWindowItemCustomization"
                and type(owner) == "table" and type(owner.release) == "function" then
            owner.release(self, "window-exit")
        end
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
            local synth = _get_synth()
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

return true
end
