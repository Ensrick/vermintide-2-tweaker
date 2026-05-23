local mod = get_mod("sample_dupe_mod")

-- Synthetic test fixture for tools/mod-lint/lint-mod.ps1.
-- Simulates the three known cim v0.7.28-alpha rehook bugs documented in
-- crafting_in_modded/CHANGELOG.md so the linter can be regression-tested.

-- Pattern 1: duplicate explicit string-form on the same class+method.
mod:hook_safe("BackendManagerPlayFab", "_create_interfaces", function()
    -- first registration
end)

mod:hook_safe("BackendManagerPlayFab", "_create_interfaces", function()
    -- second registration — VMF silently drops this one
end)

-- Pattern 2: two for-loops each hooking the same (class, method) on
-- overlapping class lists.
for _, klass in ipairs({ "CraftPageCraftItem", "CraftPageCraftItemConsole" }) do
    mod:hook_safe(klass, "setup_recipe_requirements", function(self)
        -- first wave: material-gating helper
    end)
end

for _, klass in ipairs({ "CraftPageCraftItem", "CraftPageCraftItemConsole" }) do
    mod:hook_safe(klass, "setup_recipe_requirements", function(self)
        -- second wave: jewelry slot pin — silently dropped
    end)
end

-- Pattern 3: loop hooking via a named literal table from earlier in file.
local _PAGES = { "CraftPageRollProperties", "CraftPageRollPropertiesConsole" }
for _, klass in ipairs(_PAGES) do
    mod:hook_safe(klass, "on_enter", function(self)
        -- first hook
    end)
end

mod:hook_safe("CraftPageRollProperties", "on_enter", function(self)
    -- second hook on a class from the loop list — silently dropped
end)

-- These two should NOT be flagged — different methods, different classes.
mod:hook("BackendInterfaceItemPlayfab", "get_filtered_items", function(func, self) end)
mod:hook("BackendInterfaceItemPlayfab", "set_loadout_item", function(func, self) end)
mod:hook(_G, "Localize", function(func, key) end)
