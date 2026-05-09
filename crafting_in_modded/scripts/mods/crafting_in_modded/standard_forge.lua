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

local mod = get_mod("cim")

-- ============================================================
-- Lifecycle: track when the standard forge UI is open
-- ============================================================
-- Stored on the shared `mod` object so the single commit hook in
-- crafting_in_modded.lua can check this flag without us rehooking commit
-- (rehook would warn + drop the second registration → commits leak to
-- PlayFab → "Backend rejected the challenge response -1" kick).

mod._cim_standard_forge_active = false

local function _is_active() return mod._cim_standard_forge_active end

-- Both the desktop ("HeroWindowCrafting") and inventory-tab/gamepad
-- ("HeroWindowCraftingConsole") variants need lifecycle hooks. The user's
-- Crashify trace showed `Enter Substate HeroWindowCraftingConsole` on PC —
-- the inventory crafting tab uses the Console class regardless of input
-- device, so missing this variant let the craft request through to PlayFab
-- → EAC challenge → kick (BACKEND_PLAYFAB_ERRORS.ERR_PLAYFAB_EAC_ERROR / 511).
for _, klass in ipairs({ "HeroWindowCrafting", "HeroWindowCraftingConsole" }) do
    mod:hook_safe(klass, "on_enter", function(self)
        mod._cim_standard_forge_active = true
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
    end)
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

mod:hook("BackendInterfaceCraftingPlayfab", "_get_valid_recipe", function(func, self, item_backend_ids, recipe_override)
    if not _is_active() or not recipe_override then
        return func(self, item_backend_ids, recipe_override)
    end
    local recipe = self._crafting_recipes_by_name[recipe_override]
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

local synth = {}

local function _result_for_modified(backend_id)
    return { { backend_id, [3] = 1 } }
end

-- ---- salvage: destroy each input item ----
-- For vanilla items: removal is session-only (PlayFab restores them on restart
-- because the commit-block prevented us from telling the server). For modded
-- items registered via `_cim_register_craft`: also unregister from the save
-- layer so they don't get re-injected next launch, and clear any modded-loadout
-- entry that points to the salvaged backend_id.
synth.salvage = function(self, item_backend_ids)
    local mirror = self._backend_mirror
    local result = {}
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
        result[i] = { bid, [3] = 1 }
    end
    mod:echo("[cim] Salvaged " .. tostring(#item_backend_ids) .. " item(s)" ..
             (unregistered > 0 and (" (" .. unregistered .. " modded crafts unregistered)") or ""))
    return result
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

-- ---- reroll_weapon_properties / reroll_jewellery_properties ----
local function _reroll_properties(self, item_backend_ids)
    local mirror = self._backend_mirror
    local item_interface = Managers.backend:get_interface("items")
    local weapon_bid = item_backend_ids[1]
    if not weapon_bid then return {} end
    local item = item_interface:get_item_from_id(weapon_bid)
    if not item then return {} end

    local master_key = item.key or item.ItemId
    local master = master_key and rawget(ItemMasterList, master_key)
    local prop_table = master and master.property_table_name
    local WP = rawget(_G, "WeaponProperties")
    local pool = WP and WP.combinations and prop_table and WP.combinations[prop_table]
                 and WP.combinations[prop_table].exotic
    if not pool or #pool == 0 then
        mod:echo("[cim] Reroll: no property combos for " .. tostring(prop_table))
        return {}
    end

    local saved = mod._cim_get_craft and mod._cim_get_craft(weapon_bid)
    local picked_idx, new_seen = _shuffle_pick(saved and saved.rerolled_props_indices, #pool)
    local combo = pool[picked_idx]

    local new_props = {}
    for _, pkey in ipairs(combo) do new_props[pkey] = 1.0 end

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
local function _reroll_traits(self, item_backend_ids)
    local mirror = self._backend_mirror
    local item_interface = Managers.backend:get_interface("items")
    local weapon_bid = item_backend_ids[1]
    if not weapon_bid then return {} end
    local item = item_interface:get_item_from_id(weapon_bid)
    if not item then return {} end

    local master_key = item.key or item.ItemId
    local master = master_key and rawget(ItemMasterList, master_key)
    local trait_table = master and master.trait_table_name
    local WT = rawget(_G, "WeaponTraits")
    local pool = WT and WT.combinations and trait_table and WT.combinations[trait_table]
    if not pool or #pool == 0 then
        mod:echo("[cim] Reroll: no trait pool for " .. tostring(trait_table))
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

            if input_data and input_data.slot_type then
                slots = { [input_data.slot_type] = true }
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
            for key, data in pairs(ItemMasterList) do
                if slots[data.slot_type]
                   and data.can_wield and table.contains(data.can_wield, career_name)
                   and data.item_type ~= "weapon_skin"
                   and data.rarity ~= "magic" and data.rarity ~= "promo" then
                    eligible[#eligible + 1] = key
                end
            end

            if #eligible == 0 then
                mod:echo("[cim] No eligible items for career " .. career_name)
                return nil
            end

            item_key = eligible[math.random(1, #eligible)]
        end

        -- Roll 2 max-value properties + 1 random trait from the weapon's own
        -- property/trait tables. We use the `exotic` tier (2-property combos)
        -- but tag the resulting item with `promo` rarity so the inventory
        -- shows the purple icon background that signals "modded craft".
        local rolled_props = {}
        local rolled_traits = {}
        local master = rawget(ItemMasterList, item_key)
        if master then
            local prop_table = master.property_table_name
            local trait_table = master.trait_table_name
            local WP = rawget(_G, "WeaponProperties")
            local WT = rawget(_G, "WeaponTraits")

            if WP and WP.combinations and prop_table and WP.combinations[prop_table]
               and WP.combinations[prop_table].exotic then
                local pool = WP.combinations[prop_table].exotic
                local combo = pool[math.random(1, #pool)]
                if combo then
                    for _, pkey in ipairs(combo) do
                        rolled_props[pkey] = 1.0  -- max value
                    end
                end
            end

            if WT and WT.combinations and trait_table and WT.combinations[trait_table] then
                local pool = WT.combinations[trait_table]
                local pick = pool[math.random(1, #pool)]
                local tkey = pick and pick[1]
                if tkey then rolled_traits[#rolled_traits + 1] = tkey end
            end
        end

        local cjson_mod = rawget(_G, "cjson")
        local custom_data = {
            power_level = "300",
            rarity = "promo",
        }
        if cjson_mod then
            custom_data.properties = cjson_mod.encode(rolled_props)
            custom_data.traits = cjson_mod.encode(rolled_traits)
        end

        local backend_id = Application.guid()
        local item = {
            ItemId = item_key,
            ItemInstanceId = backend_id,
            CustomData = custom_data,
        }

        local ok, err = pcall(self._backend_mirror.add_item, self._backend_mirror, backend_id, item)
        if not ok then
            mod:echo("[cim] add_item FAILED for " .. item_key .. ": " .. tostring(err))
            return nil
        end

        -- Persist so the item survives a game restart. Same save layer as the
        -- Athanor — registered with `via_mirror = true` so `_athanor_inject_all`
        -- re-creates it via backend_mirror:add_item on next session.
        if mod._cim_register_craft then
            mod._cim_register_craft(backend_id, {
                item_key = item_key,
                properties = rolled_props,
                traits = rolled_traits,
                power_level = 300,
                rarity = "promo",
                via_mirror = true,
            })
        end

        -- Verify the item is actually in the mirror after add_item
        local item_interface = Managers.backend:get_interface("items")
        local stored = item_interface and item_interface:get_item_from_id(backend_id)
        local stored_key = stored and (stored.key or (stored.data and stored.data.key)) or "<nil>"
        local stored_rarity = stored and stored.rarity or "<nil>"
        mod:echo("[cim] Crafted " .. item_key .. " (key=" .. tostring(stored_key) .. " rarity=" .. tostring(stored_rarity) .. " bid=" .. tostring(backend_id) .. ")")

        return { { backend_id, [3] = 1 } }
    end
end

synth.craft_random_item = _make_craft_synth({ melee = true, ranged = true, trinket = true, ring = true, necklace = true })
synth.craft_weapon      = _make_craft_synth({ melee = true, ranged = true })
synth.craft_jewellery   = _make_craft_synth({ trinket = true, ring = true, necklace = true })

-- Diagnostic: list every recently-added (post-load) inventory item so we can
-- see whether crafted items landed in the mirror but failed to surface in the UI.
mod:command("craft_recent", "List newly-added items in the backend mirror", function()
    local mirror = Managers.backend and Managers.backend:get_backend_mirror()
    if not mirror or not mirror._inventory_items then
        mod:echo("[cim] backend mirror not ready")
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

mod:hook("BackendInterfaceCraftingPlayfab", "craft", function(func, self, career_name, item_backend_ids, recipe_override)
    if not _is_active() then
        return func(self, career_name, item_backend_ids, recipe_override)
    end

    -- Active = standard forge UI is open. NEVER fall through to the original
    -- `craft()` here — it would enqueue an `ExecuteCloudScript` PlayFab request
    -- with `send_eac_challenge = true` (playfab_request_queue.lua:44), and in
    -- modded realm the EAC client is unavailable so the response triggers
    -- `playfab_eac_error` (reason 511) → "Backend rejected the challenge response"
    -- → quit. Any unrecognized recipe is reported and silently dropped instead.
    local recipe, valid_ids = self:_get_valid_recipe(item_backend_ids, recipe_override)
    if not recipe then
        mod:echo("[cim] Recipe '" .. tostring(recipe_override) .. "' could not be resolved (dropped to avoid EAC kick)")
        return nil
    end

    local synth_fn = synth[recipe.name]
    if not synth_fn then
        mod:echo("[cim] Recipe '" .. tostring(recipe.name) .. "' not yet implemented in modded (dropped)")
        return nil
    end

    self._last_id = (self._last_id or 0) + 1
    local id = self._last_id
    local result = synth_fn(self, item_backend_ids, recipe, recipe_override)
    self._craft_requests[id] = result or {}

    Managers.backend:dirtify_interfaces()
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
