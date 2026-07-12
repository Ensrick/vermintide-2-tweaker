-- _cos_unlocks.lua -- cosmetic unlocks + portrait frames + unobtainable-cosmetic grants.
--
-- Owns the backend-mirror injection that surfaces hats/skins/frames the player
-- would not otherwise own in the modded realm: per-career can_wield unlocks
-- (apply_cosmetic_unlocks), Unlock-All portrait frames (_inject_all_frames), and
-- the vanilla-unobtainable cosmetic grants (_inject_unobtainable_cosmetics), plus
-- the two PlayFabMirrorAdventure hooks (_create_fake_inventory_items /
-- get_unlocked_cosmetics) and the /frames_status + /cosmetics_status commands.
-- Split out of the god file in v0.9.77-dev Phase 1; no behavior change.
--
-- Owned by: cosmetics_tweaker.lua entry point. Consumed via: mod:dofile.
-- Shared state: exports mod._cos.apply_cosmetic_unlocks (the entry's
-- on_game_state_changed / on_setting_changed callbacks drive it); reads
-- mod._cos.U (managed-cosmetic map) and mod._cos.skin_requires_unowned_dlc.

local mod = get_mod("cosmetics_tweaker")
local COS = mod._cos
local U = COS.U
local _skin_requires_unowned_dlc = COS.skin_requires_unowned_dlc

-- ============================================================
-- Cosmetic unlocks (per-career within character)
-- ============================================================
-- Mirrors weapon_tweaker's apply_weapon_unlocks: strips mod-managed careers
-- from each item's `can_wield`, then re-adds only the careers whose toggle is
-- on. Items in U.map are exclusively cross-career-within-character (probe
-- excluded vs_* / wh_priest-only / cross-character entries).

local _CHARACTER_CAREERS = {
    kruber    = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" },
    bardin    = { "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer" },
    saltzpyre = { "wh_captain", "wh_bountyhunter", "wh_zealot" },  -- wh_priest excluded
    elf       = { "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" },
    sienna    = { "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer" },
}

local function apply_cosmetic_unlocks()
    if not ItemMasterList then return end

    for item_key, info in pairs(U.managed) do
        -- rawget: ItemMasterList __index crashifies on missing keys; some U.managed
        -- entries may reference items that don't exist on this user's install (DLC ownership).
        local item = rawget(ItemMasterList, item_key)
        if item then
            item.can_wield = item.can_wield or {}
            -- Build the set of careers this item should have, derived from toggles.
            local desired = {}
            for _, career in ipairs(_CHARACTER_CAREERS[info.character] or {}) do
                if mod:get("cos_unlock_" .. career .. "_" .. item_key) then
                    desired[career] = true
                end
            end
            -- Strip all of this character's careers from can_wield, then re-add
            -- only the desired ones. Other characters' careers (e.g. wh_priest
            -- on a Saltzpyre item) are left untouched.
            local char_careers = {}
            for _, c in ipairs(_CHARACTER_CAREERS[info.character] or {}) do
                char_careers[c] = true
            end
            for i = #item.can_wield, 1, -1 do
                if char_careers[item.can_wield[i]] then
                    table.remove(item.can_wield, i)
                end
            end
            for career in pairs(desired) do
                item.can_wield[#item.can_wield + 1] = career
            end
        end
    end
end

-- ============================================================
-- Unlock All Portrait Frames (modded realm only)
-- ============================================================
-- Two-pronged injection so frames show up regardless of when the
-- player toggles the setting:
--
--   1) Pre-hook on `_create_fake_inventory_items` mutates the
--      `fake_inventory_items` table parameter BEFORE the original
--      runs, ensuring fake backend IDs are minted and registered
--      into `_inventory_items`. This is the path that actually
--      makes frames show up in the UI's filtered item list.
--
--   2) Safe hook on `get_unlocked_cosmetics` keeps the table in
--      sync for any later callers that re-query (e.g. UI tooltips,
--      profile views) without going through fake inventory.
--
-- Note: `get_unlocked_cosmetics` is called once at PlayFab login
-- (inventory_request_cb). If the user toggles the setting AFTER
-- that, `_create_fake_inventory_items` won't re-run automatically,
-- so the toggle requires a full restart to take effect — the (1)
-- pre-hook still runs at next login. Documented in CHANGELOG.
--
-- DLC ownership is respected via required_dlc checks.

local _frame_inject_stats = { last_added = 0, last_skipped_dlc = 0, hook_fired = 0 }

local function _inject_all_frames(target)
    if not target then return 0, 0 end
    local added, skipped = 0, 0
    for key, data in pairs(ItemMasterList) do
        if data.item_type == "frame" and target[key] == nil then
            if _skin_requires_unowned_dlc(key) then
                skipped = skipped + 1
            else
                target[key] = true
                added = added + 1
            end
        end
    end
    return added, skipped
end

-- v0.9.63-dev: vanilla-UNOBTAINABLE cosmetics — career skins + hats that have NO
-- obtain path anywhere in the shipped data: not in Lohner's Emporium catalog
-- (store_data.lua), no premium-store / bundle entry (store_dlc_settings.lua /
-- store_bundle_layouts.lua), no steam_itemdefid, no achievement grant, no required_dlc.
-- Vanilla therefore never places them in the player's inventory, so the per-career
-- unlock toggles (which only edit can_wield in apply_cosmetic_unlocks) can never
-- surface them — the item is simply never owned. We grant modded-realm ownership by
-- injecting them into the cosmetic fake-inventory, the SAME mechanism the portrait
-- frame unlock uses: playfab_mirror_base.lua:2315-2401 turns each injected key into a
-- fake item and registers `_unlocked_cosmetics[key] = backend_id` +
-- `_inventory_items[backend_id]`. List derived from a full ItemMasterList ×
-- store/achievement/steam_itemdefid cross-reference sweep (54 skins + 82 hats). The
-- "_white" skins are the datamined "(Purified)" prestige set; the rest are
-- discontinued promo skins/hats (Nuln Bordermarcher, Ostermark Bowman, etc.).
local _unobtainable_cosmetics = {
    -- Kruber hats
    "es_hat_0001", "es_hat_0002", "es_hat_0003", "es_helmet_0003",
    "huntsman_hat_0004", "huntsman_hat_0009", "huntsman_hat_1010",
    "knight_hat_0003", "knight_hat_0005", "knight_hat_0006", "knight_hat_0011",
    "mercenary_hat_0006", "mercenary_hat_0007",
    -- Kruber skins
    "skin_es_huntsman_black_and_gold", "skin_es_huntsman_ostermark", "skin_es_huntsman_white",
    "skin_es_knight_black_and_gold", "skin_es_knight_red", "skin_es_knight_white",
    "skin_es_mercenary_black_and_gold", "skin_es_mercenary_helmgart", "skin_es_mercenary_ostermark", "skin_es_mercenary_white",
    "skin_es_questingknight_white",
    -- Bardin hats
    "dr_helmet_0001", "dr_helmet_0002", "dr_helmet_0003", "dr_helmet_0005", "dr_helmet_0008", "dr_helmet_0011",
    "dr_slayer_hair_0002",
    "ironbreaker_hat_0007", "ironbreaker_hat_0012", "ironbreaker_hat_0013",
    "ranger_hat_0003", "ranger_hat_0004", "ranger_hat_0010", "ranger_hat_0015", "ranger_hat_1010",
    "slayer_hat_0006", "slayer_hat_0007", "slayer_hat_0010", "slayer_hat_0012", "slayer_hat_1010",
    -- Bardin skins
    "skin_dr_engineer_white",
    "skin_dr_ironbreaker_black_and_gold", "skin_dr_ironbreaker_crimson", "skin_dr_ironbreaker_white",
    "skin_dr_ranger_black_and_gold", "skin_dr_ranger_helmgart", "skin_dr_ranger_karak_norn", "skin_dr_ranger_white",
    "skin_dr_slayer_dragon", "skin_dr_slayer_runes", "skin_dr_slayer_skull", "skin_dr_slayer_white",
    -- Saltzpyre hats
    "bountyhunter_hat_0002", "bountyhunter_hat_0003", "bountyhunter_hat_1010",
    "priest_hat_0001", "priest_hat_0002", "priest_hat_0003", "priest_hat_0004",
    "wh_hat_0001", "wh_hat_0003", "wh_hat_0007", "wh_hat_0008", "wh_hat_0009",
    "witchhunter_hat_0002", "witchhunter_hat_0003",
    "zealot_hat_0003", "zealot_hat_0009", "zealot_hat_0010", "zealot_hat_1003", "zealot_hat_1010",
    -- Saltzpyre skins
    "skin_wh_bountyhunter_black_and_gold", "skin_wh_bountyhunter_white", "skin_wh_bountyhunter_yellow_and_red",
    "skin_wh_captain_black_and_gold", "skin_wh_captain_helmgart", "skin_wh_captain_ostland", "skin_wh_captain_white",
    "skin_wh_zealot_black_and_gold", "skin_wh_zealot_crimson", "skin_wh_zealot_white",
    -- Kerillian hats
    "maidenguard_hat_0005", "maidenguard_hat_0008", "maidenguard_hat_0010", "maidenguard_hat_1010",
    "shade_hat_0003", "shade_hat_0007", "shade_hat_0010", "shade_hat_1010",
    "thornsister_hat_1010",
    "waywatcher_hat_0002", "waywatcher_hat_0006", "waywatcher_hat_0011", "waywatcher_hat_1010",
    "ww_hood_0001", "ww_hood_0002", "ww_hood_0004",
    -- Kerillian skins
    "skin_ww_maidenguard_black_and_gold", "skin_ww_maidenguard_red_and_yellow", "skin_ww_maidenguard_white",
    "skin_ww_shade_black_and_gold", "skin_ww_shade_crimson", "skin_ww_shade_white",
    "skin_ww_thornsister_white",
    "skin_ww_waywatcher_anmyr", "skin_ww_waywatcher_black_and_gold", "skin_ww_waywatcher_helmgart", "skin_ww_waywatcher_white",
    -- Sienna hats
    "adept_hat_0002", "adept_hat_0003", "adept_hat_0010", "adept_hat_1010",
    "bw_gate_0001", "bw_gate_0006", "bw_gate_0007", "bw_gate_0008",
    "bw_necromancer_hat_1010",
    "scholar_hat_0004", "scholar_hat_0005", "scholar_hat_0012",
    "unchained_hat_0004", "unchained_hat_0008",
    -- Sienna skins
    "skin_bw_adept_black_and_gold", "skin_bw_adept_helmgart", "skin_bw_adept_ostermark", "skin_bw_adept_white",
    "skin_bw_scholar_black_and_gold", "skin_bw_scholar_ostermark", "skin_bw_scholar_white",
    "skin_bw_unchained_black_and_gold", "skin_bw_unchained_ostermark", "skin_bw_unchained_white",
}

-- Ownership is account-wide (once owned, any career in the item's native can_wield
-- can equip it). Grant an unobtainable cosmetic when it has NO managed per-career
-- toggle (e.g. the wh_priest bless hats, which the mod's cross-career system
-- excludes), or when ANY of its character's career toggles is enabled — so the user
-- can still hide one again by unchecking all its Cosmetic Availability toggles.
local function _cosmetic_ownership_enabled(item_key)
    local info = U.managed[item_key]
    if not info then return true end
    for _, career in ipairs(_CHARACTER_CAREERS[info.character] or {}) do
        if mod:get("cos_unlock_" .. career .. "_" .. item_key) then return true end
    end
    return false
end

local _unob_inject_stats = { last_added = 0, last_skipped_dlc = 0 }
local function _inject_unobtainable_cosmetics(target)
    if not target then return 0, 0 end
    local added, skipped = 0, 0
    for i = 1, #_unobtainable_cosmetics do
        local key = _unobtainable_cosmetics[i]
        -- rawget: ItemMasterList __index crashifies on missing keys; a DLC pack the
        -- user doesn't own leaves some of these keys unregistered on their install.
        if target[key] == nil and rawget(ItemMasterList, key) then
            if _skin_requires_unowned_dlc(key) then
                skipped = skipped + 1
            elseif _cosmetic_ownership_enabled(key) then
                target[key] = true
                added = added + 1
            end
        end
    end
    _unob_inject_stats.last_added = added
    _unob_inject_stats.last_skipped_dlc = skipped
    return added, skipped
end

-- IMPORTANT: hook the DERIVED class, not `PlayFabMirrorBase`.
-- foundation\scripts\util\class.lua:51-57 copies parent methods into the
-- child table at class-definition time (no __index chaining). The runtime
-- instance is `PlayFabMirrorAdventure`, which holds its OWN copies of these
-- functions. Hooking the base class wraps a function value the runtime never
-- reaches, so the hook never fires (verified empirically: cos frames_status
-- showed "inject hook fired 0 time(s)" with the base-class hook). See log
-- 2026-05-06 02:41 for the diagnostic that surfaced this.

mod:hook("PlayFabMirrorAdventure", "_create_fake_inventory_items", function(func, self, fake_inventory_items, items_type)
    if items_type == "cosmetics" and script_data["eac-untrusted"] and fake_inventory_items then
        if mod:get("unlock_all_frames") then
            local added, skipped = _inject_all_frames(fake_inventory_items)
            _frame_inject_stats.hook_fired = _frame_inject_stats.hook_fired + 1
            _frame_inject_stats.last_added = added
            _frame_inject_stats.last_skipped_dlc = skipped
            mod:info("[unlock_all_frames] _create_fake_inventory_items pre-hook fired: added=%d skipped_dlc=%d", added, skipped)
        end
        -- v0.9.63-dev: grant modded-realm ownership of vanilla-unobtainable skins/hats
        -- so the per-career unlock toggles can actually surface them (they otherwise
        -- never enter the player's inventory). Always runs in modded realm — this is
        -- NOT gated on the frame toggle, which is a separate feature.
        local ca, cs = _inject_unobtainable_cosmetics(fake_inventory_items)
        if ca > 0 then
            mod:info("[unlock_cosmetics] injected %d unobtainable cosmetics into fake inventory (skipped_dlc=%d)", ca, cs)
        end
    end
    return func(self, fake_inventory_items, items_type)
end)

mod:hook_safe("PlayFabMirrorAdventure", "get_unlocked_cosmetics", function(self)
    if not script_data["eac-untrusted"] then return end
    local cosmetics = self._unlocked_cosmetics
    if not cosmetics then return end
    -- Belt-and-suspenders resync for callers that re-query after login. Both injectors
    -- no-op on keys already registered (they guard on `target[key] == nil`), so the
    -- pre-hook's real backend_ids are never clobbered.
    if mod:get("unlock_all_frames") then _inject_all_frames(cosmetics) end
    _inject_unobtainable_cosmetics(cosmetics)
end)

mod:command("frames_status", "Diagnostic for the Unlock All Portrait Frames toggle.", function()
    local on = mod:get("unlock_all_frames")
    local modded = script_data and script_data["eac-untrusted"]
    mod:echo("[frames_status] toggle=%s modded_realm=%s", tostring(on), tostring(modded))
    mod:echo("[frames_status] inject hook fired %d time(s); last added=%d skipped_dlc=%d",
        _frame_inject_stats.hook_fired, _frame_inject_stats.last_added, _frame_inject_stats.last_skipped_dlc)

    local total_frames, dlc_locked = 0, 0
    for _, data in pairs(ItemMasterList) do
        if data.item_type == "frame" then
            total_frames = total_frames + 1
            if data.required_dlc and Managers.unlock and not Managers.unlock:is_dlc_unlocked(data.required_dlc) then
                dlc_locked = dlc_locked + 1
            end
        end
    end
    mod:echo("[frames_status] ItemMasterList: %d frames total, %d DLC-locked", total_frames, dlc_locked)

    local backend = Managers.backend
    local mirror = backend and backend._interfaces and backend._interfaces.mirror
                 or backend and backend.get_interface and backend:get_interface("items")
    local mirror_base
    if mirror and mirror._backend_mirror then mirror_base = mirror._backend_mirror end
    if not mirror_base and backend and backend._mirror then mirror_base = backend._mirror end
    if mirror_base and mirror_base._unlocked_cosmetics then
        local n = 0
        for k, _ in pairs(mirror_base._unlocked_cosmetics) do
            if rawget(ItemMasterList, k) and ItemMasterList[k].item_type == "frame" then n = n + 1 end
        end
        mod:echo("[frames_status] _unlocked_cosmetics contains %d frame entries", n)
    else
        mod:echo("[frames_status] could not locate PlayFabMirrorBase via Managers.backend")
    end

    local items_iface = backend and backend.get_interface and backend:get_interface("items")
    if items_iface and items_iface.get_filtered_items then
        local list = items_iface:get_filtered_items("slot_type == frame", {})
        mod:echo("[frames_status] backend get_filtered_items('slot_type == frame') returned %d items", list and #list or -1)
    end
end)

-- v0.9.63-dev: verify the unobtainable-cosmetic ownership grant in-game (user runs
-- with mod-logging OFF, so the mod:info lines above are invisible; this echoes to chat).
mod:command("cosmetics_status", "Diagnostic for the vanilla-unobtainable skin/hat unlock.", function()
    mod:echo("[cosmetics_status] modded_realm=%s | last inject: added=%d skipped_dlc=%d (of %d tracked)",
        tostring(script_data and script_data["eac-untrusted"]),
        _unob_inject_stats.last_added, _unob_inject_stats.last_skipped_dlc, #_unobtainable_cosmetics)
    local backend = Managers.backend
    local mirror = backend and backend.get_interface and backend:get_interface("items")
    local mirror_base = mirror and mirror._backend_mirror
    if not mirror_base and backend then mirror_base = backend._mirror end
    if mirror_base and mirror_base._unlocked_cosmetics then
        local owned, missing = 0, {}
        for i = 1, #_unobtainable_cosmetics do
            local k = _unobtainable_cosmetics[i]
            if mirror_base._unlocked_cosmetics[k] then owned = owned + 1
            elseif rawget(ItemMasterList, k) then missing[#missing + 1] = k end
        end
        mod:echo("[cosmetics_status] %d/%d unobtainable cosmetics owned in _unlocked_cosmetics", owned, #_unobtainable_cosmetics)
        if #missing > 0 then
            mod:echo("[cosmetics_status] %d present-but-unowned (toggle off or not yet synced): %s%s",
                #missing, table.concat(missing, ", ", 1, math.min(#missing, 8)), #missing > 8 and " ..." or "")
        end
    else
        mod:echo("[cosmetics_status] could not locate PlayFabMirrorBase via Managers.backend")
    end
end)

-- Export so the entry's lifecycle callbacks (on_game_state_changed /
-- on_setting_changed) can drive the per-career unlock re-apply.
mod._cos.apply_cosmetic_unlocks = apply_cosmetic_unlocks
