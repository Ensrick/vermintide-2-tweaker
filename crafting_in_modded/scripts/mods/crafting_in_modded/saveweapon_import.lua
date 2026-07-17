--[[
saveweapon_import — One-shot importer: every weapon the player saved with the
SaveWeapon mod (workshop ID 1687843693) becomes a cim modded craft.

UX:
  /cim_import_saved_weapons     -- chat command (also bindable as a VMF keybind)

Idempotent: a dedupe key of (item_key, sorted_props, sorted_traits, skin)
matches existing _forged_weapons entries, so re-running is a no-op for
already-imported items.

Source-of-truth schema (from SaveWeapon.lua:512-540):
  saved_items[<item_key>_<numeric_id>] = "<favorite>/<skin_or_nil>/<trait>/<prop1>/<prop2>/..."
SaveWeapon writes every property at value=1.0 on recreation
(SaveWeapon.lua:561-564); we do the same.
]]

local mod = get_mod("cim")

local SAVEWEAPON_MOD_ID = "SaveWeapon"

-- Mirror standard_forge's helper. The forge version is file-scope-local and
-- isn't exposed via the mod table, so we inline the same logic here. Both
-- helpers stay in lock-step because they share the vanilla pattern.
local function _requires_unowned_dlc(item_key)
    if not item_key or not ItemMasterList then return false end
    local data = rawget(ItemMasterList, item_key)
    if not data or not data.required_dlc then return false end
    if not Managers.unlock then return false end
    return not Managers.unlock:is_dlc_unlocked(data.required_dlc)
end

-- Stable dedupe key. Properties and traits are sorted alphabetically so the
-- same logical item produces the same signature regardless of how SaveWeapon
-- ordered them in the savestring.
local function _signature(item_key, props_list, traits_list, skin)
    local sorted_props = {}
    for _, p in ipairs(props_list) do sorted_props[#sorted_props + 1] = p end
    table.sort(sorted_props)
    local sorted_traits = {}
    for _, t in ipairs(traits_list) do sorted_traits[#sorted_traits + 1] = t end
    table.sort(sorted_traits)
    return tostring(item_key) .. "|" ..
        table.concat(sorted_props, ",") .. "|" ..
        table.concat(sorted_traits, ",") .. "|" ..
        tostring(skin or "")
end

local function _existing_signatures()
    local set = {}
    local saved = mod:get("forged_weapons") or {}
    for _, w in pairs(saved) do
        if w and w.item_key then
            local props_list = {}
            for k in pairs(w.properties or {}) do props_list[#props_list + 1] = k end
            local traits_list = w.traits or (w.trait and { w.trait }) or {}
            set[_signature(w.item_key, props_list, traits_list, w.skin)] = true
        end
    end
    return set
end

-- Parse "fav/skin_or_nil/trait/p1/p2/..." → table. Returns nil if malformed.
local function _parse_savestring(savestring)
    if type(savestring) ~= "string" then return nil end
    local parts = {}
    for s in savestring:gmatch("[^/]+") do parts[#parts + 1] = s end
    if #parts < 3 then return nil end
    local skin = parts[2]
    if skin == "nil" or skin == "" then skin = nil end
    local trait = parts[3]
    if trait == "nil" or trait == "" then trait = nil end
    local props = {}
    for i = 4, #parts do
        if parts[i] and parts[i] ~= "" and parts[i] ~= "nil" then
            props[#props + 1] = parts[i]
        end
    end
    return {
        favorite   = parts[1] == "true",
        skin       = skin,
        trait      = trait,
        properties = props,
    }
end

-- Recover the vanilla ItemMasterList key from SaveWeapon's `<item_key>_<id>`
-- save_id. Prefer SaveWeapon's own `get_item_name_from_save_id` (the v1.2.5
-- rewrite catches edge cases like Bretonnian S&S vs regular S&S that a naïve
-- strip-trailing-digits would mis-classify); fall back to the strip if the
-- helper isn't reachable from this scope.
local function _item_key_from_save_id(save_id, sw_mod)
    if sw_mod and sw_mod.get_item_name_from_save_id then
        local ok, key = pcall(sw_mod.get_item_name_from_save_id, sw_mod, save_id)
        if ok and key and ItemMasterList and rawget(ItemMasterList, key) then
            return key
        end
    end
    local stripped = tostring(save_id):gsub("_%d+$", "")
    if ItemMasterList and rawget(ItemMasterList, stripped) then return stripped end
    return nil
end

mod._cim_saveweapon_import = function()
    local sw_mod = get_mod(SAVEWEAPON_MOD_ID)
    if not sw_mod then
        mod:echo("[cim] SaveWeapon mod not installed — nothing to import.")
        return
    end
    local saved_items = sw_mod:get("saved_items")
    if type(saved_items) ~= "table" or not next(saved_items) then
        mod:echo("[cim] SaveWeapon has no saved items.")
        return
    end

    local mirror = Managers.backend and Managers.backend:get_backend_mirror()
    if not mirror then
        mod:echo("[cim] Backend mirror not ready — open the keep first then try again.")
        return
    end

    local seen = _existing_signatures()
    local cjson_mod = rawget(_G, "cjson")
    local imported, skipped_dup, skipped_dlc, skipped_bad = 0, 0, 0, 0

    for save_id, savestring in pairs(saved_items) do
        local parsed = _parse_savestring(savestring)
        local item_key = parsed and _item_key_from_save_id(save_id, sw_mod)

        if not parsed or not item_key then
            skipped_bad = skipped_bad + 1
            mod:info("[saveweapon-import] skipping '%s' (parse fail or unknown item_key)", tostring(save_id))
        elseif _requires_unowned_dlc(item_key) then
            skipped_dlc = skipped_dlc + 1
            mod:info("[saveweapon-import] skipping '%s' (requires unowned DLC)", tostring(item_key))
        else
            local props_list  = parsed.properties or {}
            local traits_list = parsed.trait and { parsed.trait } or {}
            local sig = _signature(item_key, props_list, traits_list, parsed.skin)
            if seen[sig] then
                skipped_dup = skipped_dup + 1
            else
                -- Validate properties and traits against the item's own
                -- property/trait tables. SaveWeapon's predecessor (GiveWeapon)
                -- doesn't enforce this — drop mismatched entries with a log
                -- line instead of refusing the whole import.
                local master = rawget(ItemMasterList, item_key)
                local WP = rawget(_G, "WeaponProperties")
                local WT = rawget(_G, "WeaponTraits")
                local valid_props = {}
                if WP and WP.properties then
                    for _, p in ipairs(props_list) do
                        if WP.properties[p] then
                            valid_props[p] = 1.0
                        else
                            mod:info("[saveweapon-import] dropping invalid property '%s' for %s", p, item_key)
                        end
                    end
                else
                    for _, p in ipairs(props_list) do valid_props[p] = 1.0 end
                end
                local valid_traits = {}
                if WT and WT.traits then
                    for _, t in ipairs(traits_list) do
                        if WT.traits[t] then
                            valid_traits[#valid_traits + 1] = t
                        else
                            mod:info("[saveweapon-import] dropping invalid trait '%s' for %s", t, item_key)
                        end
                    end
                else
                    for _, t in ipairs(traits_list) do valid_traits[#valid_traits + 1] = t end
                end

                local backend_id = Application.guid()
                local contract = mod._cim_synthetic_item_contract
                local master = rawget(ItemMasterList, item_key)
                local record, record_err = contract and contract.normalize_record(backend_id, {
                    item_key = item_key,
                    properties = valid_props,
                    traits = valid_traits,
                    trait = valid_traits[1],
                    skin = parsed.skin,
                    power_level = 300,
                    rarity = "modded",
                    via_mirror = true,
                }, master)
                local encoder = cjson_mod and cjson_mod.encode
                local item, payload_err = record
                    and contract.build_mirror_payload(record, master, encoder)
                if not item then
                    skipped_bad = skipped_bad + 1
                    mod:info("[saveweapon-import] contract rejected %s: %s",
                        item_key, tostring(record_err or payload_err))
                else
                local add_ok, add_err = pcall(mirror.add_item, mirror, backend_id, item)
                if not add_ok then
                    skipped_bad = skipped_bad + 1
                    mod:info("[saveweapon-import] add_item failed for %s: %s", item_key, tostring(add_err))
                else
                    local registered, register_err = mod._cim_register_craft(backend_id, record)
                    if not registered then
                        mirror:remove_item(backend_id)
                        skipped_bad = skipped_bad + 1
                        mod:info("[saveweapon-import] persistence rejected %s: %s",
                            item_key, tostring(register_err))
                    else
                        seen[sig] = true
                        imported = imported + 1
                    end
                end
                end
            end
        end
    end

    -- Refresh the items interface so the inventory grid picks up the new
    -- items immediately (the user usually has the inventory open when they
    -- run the import).
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    if items_iface and items_iface._refresh then pcall(items_iface._refresh, items_iface) end
    -- v0.7.60-dev: this path injects via its own mirror:add_item (NOT
    -- _athanor_inject_item), so it did not inherit the v0.7.59 fix. Mark the
    -- backend interfaces dirty so the open inventory UI re-queries — same fix
    -- that made Athanor/standard-forge crafts appear without a menu re-open.
    if Managers.backend and Managers.backend.dirtify_interfaces then
        pcall(Managers.backend.dirtify_interfaces, Managers.backend)
    end

    mod:echo(string.format(
        "[cim] SaveWeapon import: %d imported, %d duplicate(s) skipped, %d locked behind unowned DLC, %d invalid",
        imported, skipped_dup, skipped_dlc, skipped_bad))
end

mod:command("cim_import_saved_weapons",
    "Import every weapon saved with the SaveWeapon mod into your cim modded inventory (idempotent — re-running skips duplicates)",
    function() mod._cim_saveweapon_import() end)
